#define _POSIX_C_SOURCE 200809L
#include "bdos.h"
#include "ansi.h"

#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>
#include <unistd.h>

static uint8_t ram_read8(const CpmVm *vm, uint16_t addr) {
    return vm->ram[addr];
}

static void ram_write8(CpmVm *vm, uint16_t addr, uint8_t val) {
    vm->ram[addr] = val;
}

static void ram_write16(CpmVm *vm, uint16_t addr, uint16_t val) {
    vm->ram[addr] = (uint8_t)(val & 0xFF);
    vm->ram[(uint16_t)(addr + 1)] = (uint8_t)((val >> 8) & 0xFF);
}

const char *cpm_status_name(CpmStatus st) {
    switch (st) {
    case CPM_RUNNING:    return "running";
    case CPM_EXITED:     return "exited";
    case CPM_HALTED:     return "halted";
    case CPM_WAIT_INPUT: return "wait_input";
    case CPM_IDLE:       return "idle";
    case CPM_BREAKPOINT: return "breakpoint";
    case CPM_STEP_LIMIT: return "step_limit";
    case CPM_FAULT:      return "fault";
    default:             return "unknown";
    }
}

void cpm_vm_init(CpmVm *vm) {
    memset(vm, 0, sizeof(*vm));
    vm->tpa_top = 0xE000;
    vm->dma_addr = 0x0080;
    vm->idle_poll_threshold = 512;
    vm->strict_bdos = true;
    vm->layout = CPM_LAYOUT_AUTO;
    snprintf(vm->workdir, sizeof(vm->workdir), ".");
    vm->echo_stdout = true;
    ansi_init(&vm->screen, 24, 80);
}

void cpm_vm_free(CpmVm *vm) {
    free(vm->search_matches);
    vm->search_matches = NULL;
    vm->search_count = 0;
    vm->search_idx = 0;
    free(vm->in_buf);
    vm->in_buf = NULL;
    vm->in_head = vm->in_tail = vm->in_cap = 0;
    free(vm->out_buf);
    vm->out_buf = NULL;
    vm->out_len = vm->out_cap = 0;
}

void cpm_push_input(CpmVm *vm, const uint8_t *data, size_t len) {
    size_t queued;
    size_t i;
    if (len == 0) return;
    queued = vm->in_tail - vm->in_head;
    if (vm->in_tail + len > vm->in_cap) {
        if (vm->in_head > 0 && queued + len <= vm->in_cap) {
            memmove(vm->in_buf, vm->in_buf + vm->in_head, queued);
            vm->in_head = 0;
            vm->in_tail = queued;
        } else {
            size_t new_cap = vm->in_cap ? vm->in_cap : 1024;
            while (new_cap < queued + len) new_cap *= 2;
            uint8_t *nb = (uint8_t *)malloc(new_cap);
            if (!nb) return;
            if (queued > 0) memcpy(nb, vm->in_buf + vm->in_head, queued);
            free(vm->in_buf);
            vm->in_buf = nb;
            vm->in_head = 0;
            vm->in_tail = queued;
            vm->in_cap = new_cap;
        }
    }
    for (i = 0; i < len; i++) {
        vm->in_buf[vm->in_tail++] = data[i];
    }
    vm->idle_polls = 0;
}

void cpm_clear_input(CpmVm *vm) {
    vm->in_head = 0;
    vm->in_tail = 0;
}

size_t cpm_input_len(const CpmVm *vm) {
    return vm->in_tail - vm->in_head;
}

static bool cpm_input_available(CpmVm *vm) {
    if (vm->stop_flag && *vm->stop_flag) {
        vm->status = CPM_EXITED;
        vm->exit_code = 130;
        snprintf(vm->exit_reason, sizeof(vm->exit_reason), "signal");
        return false;
    }
    if (vm->in_tail > vm->in_head) return true;
    if (!vm->stop_on_wait_input && !vm->stdin_eof) {
        struct pollfd pfd;
        int timeout_ms = (vm->interactive_tty && vm->idle_polls >= 300) ? 5 : 0;
        pfd.fd = STDIN_FILENO;
        pfd.events = POLLIN;
        if (poll(&pfd, 1, timeout_ms) == 1 && (pfd.revents & POLLIN)) {
            uint8_t buf[64];
            ssize_t nr = read(STDIN_FILENO, buf, sizeof(buf));
            if (nr > 0) {
                for (ssize_t k = 0; k < nr; k++) {
                    if (buf[k] == '\n') buf[k] = '\r';
                }
                cpm_push_input(vm, buf, (size_t)nr);
                return true;
            }
            if (nr == 0) {
                vm->stdin_eof = true;
            }
        }
    }
    return false;
}

static bool cpm_read_input_nonblock(CpmVm *vm, uint8_t *out) {
    if (!cpm_input_available(vm)) return false;
    *out = vm->in_buf[vm->in_head++];
    if (vm->in_head == vm->in_tail) {
        vm->in_head = vm->in_tail = 0;
    }
    return true;
}

static bool cpm_read_input_blocking(CpmVm *vm, uint8_t *out, bool *is_eof) {
    if (is_eof) *is_eof = false;
    if (cpm_read_input_nonblock(vm, out)) {
        return true;
    }
    if (vm->stop_on_wait_input) {
        vm->status = CPM_WAIT_INPUT;
        return false;
    }
    if (vm->stdin_eof) {
        *out = 0x1A;
        if (is_eof) *is_eof = true;
        return true;
    }
    {
        uint8_t b = 0;
        ssize_t nr = read(STDIN_FILENO, &b, 1);
        if (nr == 1) {
            if (b == '\n') b = '\r';
            *out = b;
            return true;
        }
        if (nr < 0 && errno == EINTR && vm->stop_flag && *vm->stop_flag) {
            vm->status = CPM_EXITED;
            vm->exit_code = 130;
            snprintf(vm->exit_reason, sizeof(vm->exit_reason), "signal");
            return false;
        }
        vm->stdin_eof = true;
        *out = 0x1A; /* CP/M EOF */
        if (is_eof) *is_eof = true;
        return true;
    }
}

static void cpm_emit_char(CpmVm *vm, uint8_t ch) {
    if (vm->mask_7bit) ch &= 0x7F;
    if (!vm->interactive_tty) {
        if (vm->out_len + 1 >= vm->out_cap) {
            size_t new_cap = vm->out_cap ? vm->out_cap * 2 : 4096;
            uint8_t *nb = (uint8_t *)realloc(vm->out_buf, new_cap);
            if (nb) {
                vm->out_buf = nb;
                vm->out_cap = new_cap;
            }
        }
        if (vm->out_len < vm->out_cap) {
            vm->out_buf[vm->out_len++] = ch;
        }
    }
    ansi_putc(&vm->screen, ch);
    if (vm->echo_stdout) {
        putchar(ch);
        fflush(stdout);
    }
}

static void cpm_emit_str(CpmVm *vm, const char *s) {
    while (*s) {
        cpm_emit_char(vm, (uint8_t)*s++);
    }
}

static bool is_dir_exists(const char *path) {
    struct stat st;
    return stat(path, &st) == 0 && S_ISDIR(st.st_mode);
}

static bool is_reg_exists(const char *path) {
    struct stat st;
    return stat(path, &st) == 0 && S_ISREG(st.st_mode);
}

static CpmLayoutMode effective_layout(const CpmVm *vm) {
    char probe[1100];
    if (vm->layout != CPM_LAYOUT_AUTO) {
        return vm->layout;
    }
    snprintf(probe, sizeof(probe), "%s/A/0", vm->workdir);
    if (is_dir_exists(probe)) {
        return CPM_LAYOUT_RUNCPM;
    }
    return CPM_LAYOUT_FLAT;
}

static bool resolve_drive_dir(const CpmVm *vm, uint8_t drive, char *out_dir, size_t out_cap, bool create_user) {
    char sub[1100];
    CpmLayoutMode mode;
    if (drive >= 16) return false;
    if (vm->drive_explicit[drive]) {
        if (!is_dir_exists(vm->drive_paths[drive])) return false;
        snprintf(out_dir, out_cap, "%s", vm->drive_paths[drive]);
        return true;
    }
    mode = effective_layout(vm);
    if (mode == CPM_LAYOUT_RUNCPM) {
        char dch = (char)('A' + drive);
        char uch = (char)(vm->user_code < 10 ? ('0' + vm->user_code) : ('A' + vm->user_code - 10));
        snprintf(sub, sizeof(sub), "%s/%c", vm->workdir, dch);
        if (!is_dir_exists(sub)) return false;
        snprintf(out_dir, out_cap, "%s/%c/%c", vm->workdir, dch, uch);
        if (create_user && !is_dir_exists(out_dir)) {
            mkdir(out_dir, 0755);
        }
        return is_dir_exists(out_dir);
    }

    /* Flat layout */
    snprintf(sub, sizeof(sub), "%s/%c", vm->workdir, (char)('A' + drive));
    if (is_dir_exists(sub)) {
        snprintf(out_dir, out_cap, "%s", sub);
        return true;
    }
    if (drive == 0 || !vm->strict_drives) {
        if (!is_dir_exists(vm->workdir)) return false;
        snprintf(out_dir, out_cap, "%s", vm->workdir);
        return true;
    }
    return false;
}

static bool fcb_extract_83(const CpmVm *vm, uint16_t fcb_addr, uint8_t *out_drive, uint8_t out_name11[11], char *out_upper, size_t cap) {
    uint8_t dr = ram_read8(vm, fcb_addr);
    int i, nlen = 0, elen = 0;
    char fn[9], ext[4];
    *out_drive = (dr == 0 || dr == '?') ? vm->cur_drive : (uint8_t)(dr - 1);
    if (*out_drive >= 16) return false;

    for (i = 0; i < 8; i++) {
        uint8_t c = (uint8_t)(ram_read8(vm, (uint16_t)(fcb_addr + 1 + i)) & 0x7F);
        if (c == '/') c = '_';
        c = (uint8_t)toupper(c);
        out_name11[i] = c;
        fn[i] = (char)c;
        if (c > ' ') nlen = i + 1;
    }
    fn[nlen] = '\0';

    for (i = 0; i < 3; i++) {
        uint8_t c = (uint8_t)(ram_read8(vm, (uint16_t)(fcb_addr + 9 + i)) & 0x7F);
        if (c == '/') c = '_';
        c = (uint8_t)toupper(c);
        out_name11[8 + i] = c;
        ext[i] = (char)c;
        if (c > ' ') elen = i + 1;
    }
    ext[elen] = '\0';

    if (nlen == 0) return false;
    for (i = 0; i < nlen; i++) {
        if (fn[i] == ' ' || fn[i] == '\\' || fn[i] == ':') return false;
    }
    for (i = 0; i < elen; i++) {
        if (ext[i] == ' ' || ext[i] == '\\' || ext[i] == ':') return false;
    }
    if (strcmp(fn, ".") == 0 || strcmp(fn, "..") == 0) return false;

    if (out_upper) {
        if (elen > 0) {
            snprintf(out_upper, cap, "%s.%s", fn, ext);
        } else {
            snprintf(out_upper, cap, "%s", fn);
        }
    }
    return true;
}

static bool host_name_to_83(const char *host_name, uint8_t out_11[11]) {
    const char *dot = strchr(host_name, '.');
    int i = 0;
    const char *p = host_name;
    if (host_name[0] == '\0' || strcmp(host_name, ".") == 0 || strcmp(host_name, "..") == 0) {
        return false;
    }
    memset(out_11, ' ', 11);
    while (*p && p != dot) {
        if (i >= 8 || *p == ' ' || *p == '/') return false;
        out_11[i++] = (uint8_t)toupper((unsigned char)*p++);
    }
    if (i == 0) return false;
    if (dot) {
        p = dot + 1;
        if (strchr(p, '.') != NULL) return false;
        i = 0;
        while (*p) {
            if (i >= 3 || *p == ' ' || *p == '/') return false;
            out_11[8 + i++] = (uint8_t)toupper((unsigned char)*p++);
        }
    }
    return true;
}

static bool match_83(const uint8_t name11[11], const uint8_t pat11[11]) {
    int i;
    for (i = 0; i < 11; i++) {
        if (pat11[i] != '?' && pat11[i] != name11[i]) return false;
    }
    return true;
}

static bool resolve_existing_file(const CpmVm *vm, uint16_t fcb_addr, char *out_path, size_t out_cap, uint8_t *out_drive) {
    uint8_t drive = 0;
    uint8_t pat[11];
    char upper_name[32];
    char dir_path[1100];
    DIR *dp;
    struct dirent *de;

    if (!fcb_extract_83(vm, fcb_addr, &drive, pat, upper_name, sizeof(upper_name))) {
        return false;
    }
    if (out_drive) *out_drive = drive;
    if (!resolve_drive_dir(vm, drive, dir_path, sizeof(dir_path), false)) {
        return false;
    }
    snprintf(out_path, out_cap, "%s/%s", dir_path, upper_name);
    if (is_reg_exists(out_path)) {
        return true;
    }

    dp = opendir(dir_path);
    if (!dp) return false;
    while ((de = readdir(dp)) != NULL) {
        if (strcasecmp(de->d_name, upper_name) == 0) {
            snprintf(out_path, out_cap, "%s/%s", dir_path, de->d_name);
            if (is_reg_exists(out_path)) {
                closedir(dp);
                return true;
            }
        }
    }
    closedir(dp);
    return false;
}

static bool resolve_new_file_path(const CpmVm *vm, uint16_t fcb_addr, char *out_path, size_t out_cap, uint8_t *out_drive) {
    uint8_t drive = 0;
    uint8_t pat[11];
    char upper_name[32];
    char dir_path[1100];
    if (!fcb_extract_83(vm, fcb_addr, &drive, pat, upper_name, sizeof(upper_name))) {
        return false;
    }
    if (memchr(pat, '?', 11) != NULL) return false;
    if (out_drive) *out_drive = drive;
    if (!resolve_drive_dir(vm, drive, dir_path, sizeof(dir_path), true)) {
        return false;
    }
    snprintf(out_path, out_cap, "%s/%s", dir_path, upper_name);
    return true;
}

static long get_file_size(const char *path) {
    struct stat st;
    if (stat(path, &st) != 0 || !S_ISREG(st.st_mode)) return -1;
    return (long)st.st_size;
}

static int cmp_dir_match(const void *a, const void *b) {
    const CpmDirMatch *ma = (const CpmDirMatch *)a;
    const CpmDirMatch *mb = (const CpmDirMatch *)b;
    return memcmp(ma->cpm_name, mb->cpm_name, 11);
}

static void emit_dir_entry(CpmVm *vm, const CpmDirMatch *m) {
    uint16_t dma = vm->dma_addr;
    uint16_t i;
    uint32_t recs;
    for (i = 0; i < 32; i++) {
        ram_write8(vm, (uint16_t)(dma + i), 0x00);
    }
    ram_write8(vm, dma, vm->user_code);
    for (i = 0; i < 11; i++) {
        ram_write8(vm, (uint16_t)(dma + 1 + i), m->cpm_name[i]);
    }
    recs = (m->size_bytes + 127U) / 128U;
    ram_write8(vm, (uint16_t)(dma + 12), 0x00);
    ram_write8(vm, (uint16_t)(dma + 14), 0x00);
    ram_write8(vm, (uint16_t)(dma + 15), (uint8_t)(recs > 128 ? 128 : recs));
}

static uint16_t bdos_search_first(CpmVm *vm, uint16_t fcb_addr) {
    uint8_t drive = 0;
    uint8_t pat[11];
    char dir_path[1100];
    DIR *dp;
    struct dirent *de;
    size_t cap = 0;

    free(vm->search_matches);
    vm->search_matches = NULL;
    vm->search_count = 0;
    vm->search_idx = 0;

    if (!fcb_extract_83(vm, fcb_addr, &drive, pat, NULL, 0)) {
        return 0x00FF;
    }
    if (!resolve_drive_dir(vm, drive, dir_path, sizeof(dir_path), false)) {
        return 0x00FF;
    }
    vm->search_drive = drive;

    dp = opendir(dir_path);
    if (!dp) return 0x00FF;
    while ((de = readdir(dp)) != NULL) {
        uint8_t cpm11[11];
        char full[1400];
        struct stat st;
        if (!host_name_to_83(de->d_name, cpm11)) continue;
        if (!match_83(cpm11, pat)) continue;
        snprintf(full, sizeof(full), "%s/%s", dir_path, de->d_name);
        if (stat(full, &st) != 0 || !S_ISREG(st.st_mode)) continue;
        if (vm->search_count >= cap) {
            size_t nc = cap ? cap * 2 : 32;
            CpmDirMatch *nm = (CpmDirMatch *)realloc(vm->search_matches, nc * sizeof(CpmDirMatch));
            if (!nm) break;
            vm->search_matches = nm;
            cap = nc;
        }
        snprintf(vm->search_matches[vm->search_count].host_name,
                 sizeof(vm->search_matches[vm->search_count].host_name), "%s", de->d_name);
        memcpy(vm->search_matches[vm->search_count].cpm_name, cpm11, 11);
        vm->search_matches[vm->search_count].size_bytes = (uint32_t)st.st_size;
        vm->search_count++;
    }
    closedir(dp);

    if (vm->search_count == 0) {
        return 0x00FF;
    }
    qsort(vm->search_matches, vm->search_count, sizeof(CpmDirMatch), cmp_dir_match);
    emit_dir_entry(vm, &vm->search_matches[0]);
    vm->search_idx = 1;
    return 0x0000;
}

static uint16_t bdos_search_next(CpmVm *vm) {
    if (vm->search_idx >= vm->search_count) {
        return 0x00FF;
    }
    emit_dir_entry(vm, &vm->search_matches[vm->search_idx]);
    vm->search_idx++;
    return 0x0000;
}

static void open_fcb_clear_all(CpmVm *vm) {
    memset(vm->open_fcbs, 0, sizeof(vm->open_fcbs));
}

static bool open_fcb_mark(CpmVm *vm, uint16_t fcb_addr, uint8_t drive, const uint8_t name11[11]) {
    size_t i;
    ssize_t free_idx = -1;
    for (i = 0; i < CPM_MAX_OPEN_FCBS; i++) {
        if (vm->open_fcbs[i].active && vm->open_fcbs[i].fcb_addr == fcb_addr) {
            vm->open_fcbs[i].drive = drive;
            memcpy(vm->open_fcbs[i].name11, name11, 11);
            return true;
        }
        if (!vm->open_fcbs[i].active && free_idx < 0) {
            free_idx = (ssize_t)i;
        }
    }
    if (free_idx < 0) return false;
    vm->open_fcbs[free_idx].active = true;
    vm->open_fcbs[free_idx].fcb_addr = fcb_addr;
    vm->open_fcbs[free_idx].drive = drive;
    memcpy(vm->open_fcbs[free_idx].name11, name11, 11);
    return true;
}

static bool open_fcb_is_open(const CpmVm *vm, uint16_t fcb_addr, uint8_t drive, const uint8_t name11[11]) {
    size_t i;
    for (i = 0; i < CPM_MAX_OPEN_FCBS; i++) {
        if (vm->open_fcbs[i].active &&
            vm->open_fcbs[i].fcb_addr == fcb_addr &&
            vm->open_fcbs[i].drive == drive &&
            memcmp(vm->open_fcbs[i].name11, name11, 11) == 0) {
            return true;
        }
    }
    return false;
}

static void open_fcb_clear_addr(CpmVm *vm, uint16_t fcb_addr) {
    size_t i;
    for (i = 0; i < CPM_MAX_OPEN_FCBS; i++) {
        if (vm->open_fcbs[i].active && vm->open_fcbs[i].fcb_addr == fcb_addr) {
            vm->open_fcbs[i].active = false;
        }
    }
}

static void open_fcb_clear_file(CpmVm *vm, uint8_t drive, const uint8_t name11[11]) {
    size_t i;
    for (i = 0; i < CPM_MAX_OPEN_FCBS; i++) {
        if (vm->open_fcbs[i].active &&
            vm->open_fcbs[i].drive == drive &&
            memcmp(vm->open_fcbs[i].name11, name11, 11) == 0) {
            vm->open_fcbs[i].active = false;
        }
    }
}

static bool check_fcb_open(const CpmVm *vm, uint16_t fcb_addr) {
    uint8_t drive = 0;
    uint8_t pat[11];
    if (!vm->strict_bdos) return true;
    if (!fcb_extract_83(vm, fcb_addr, &drive, pat, NULL, 0)) return false;
    return open_fcb_is_open(vm, fcb_addr, drive, pat);
}

static uint16_t bdos_open(CpmVm *vm, uint16_t fcb_addr) {
    char path[1400];
    uint8_t drive = 0;
    uint8_t pat[11];
    long fsize;
    long total_recs;
    uint32_t ex;
    long ext_recs;
    int i;

    if (!fcb_extract_83(vm, fcb_addr, &drive, pat, NULL, 0)) {
        return 0x00FF;
    }
    if (!resolve_existing_file(vm, fcb_addr, path, sizeof(path), &drive)) {
        return 0x00FF;
    }
    fsize = get_file_size(path);
    if (fsize < 0) return 0x00FF;
    if (vm->strict_bdos && !open_fcb_mark(vm, fcb_addr, drive, pat)) {
        return 0x00FF;
    }

    vm->login_vec |= (uint16_t)(1U << drive);
    total_recs = (fsize + 127L) / 128L;
    ex = ((uint32_t)(ram_read8(vm, (uint16_t)(fcb_addr + 14)) & 0x0F) << 5) |
         (uint32_t)(ram_read8(vm, (uint16_t)(fcb_addr + 12)) & 0x1F);
    ext_recs = total_recs - (long)ex * 128L;
    if (ext_recs < 0) ext_recs = 0;
    if (ext_recs > 128) ext_recs = 128;

    ram_write8(vm, (uint16_t)(fcb_addr + 13), 0x00);
    ram_write8(vm, (uint16_t)(fcb_addr + 14), (uint8_t)(ram_read8(vm, (uint16_t)(fcb_addr + 14)) | 0x80));
    ram_write8(vm, (uint16_t)(fcb_addr + 15), (uint8_t)ext_recs);
    for (i = 0; i < 16; i++) {
        ram_write8(vm, (uint16_t)(fcb_addr + 16 + i), 0x00);
    }
    return 0x0000;
}

static uint16_t bdos_close(CpmVm *vm, uint16_t fcb_addr) {
    char path[1400];
    uint8_t drive = 0;
    uint8_t pat[11];
    if (!fcb_extract_83(vm, fcb_addr, &drive, pat, NULL, 0)) {
        return 0x00FF;
    }
    if (vm->strict_bdos && !open_fcb_is_open(vm, fcb_addr, drive, pat)) {
        return 0x00FF;
    }
    open_fcb_clear_addr(vm, fcb_addr);
    if (!resolve_existing_file(vm, fcb_addr, path, sizeof(path), &drive)) {
        return 0x00FF;
    }
    ram_write8(vm, (uint16_t)(fcb_addr + 14), (uint8_t)(ram_read8(vm, (uint16_t)(fcb_addr + 14)) | 0x80));
    return 0x0000;
}

static uint16_t bdos_make(CpmVm *vm, uint16_t fcb_addr) {
    char path[1400], existing_path[1400];
    uint8_t drive = 0;
    uint8_t pat[11];
    FILE *fp;
    int i;
    if (!fcb_extract_83(vm, fcb_addr, &drive, pat, NULL, 0)) {
        return 0x00FF;
    }
    if (!resolve_new_file_path(vm, fcb_addr, path, sizeof(path), &drive)) {
        return 0x00FF;
    }
    if (vm->ro_vec & (1U << drive)) return 0x00FF;
    if (vm->strict_bdos && resolve_existing_file(vm, fcb_addr, existing_path, sizeof(existing_path), &drive)) {
        return 0x00FF;
    }
    fp = fopen(path, "wb");
    if (!fp) return 0x00FF;
    fclose(fp);
    if (vm->strict_bdos && !open_fcb_mark(vm, fcb_addr, drive, pat)) {
        return 0x00FF;
    }
    vm->login_vec |= (uint16_t)(1U << drive);
    ram_write8(vm, (uint16_t)(fcb_addr + 12), 0x00);
    ram_write8(vm, (uint16_t)(fcb_addr + 13), 0x00);
    ram_write8(vm, (uint16_t)(fcb_addr + 14), 0x00);
    ram_write8(vm, (uint16_t)(fcb_addr + 15), 0x00);
    for (i = 0; i < 16; i++) {
        ram_write8(vm, (uint16_t)(fcb_addr + 16 + i), 0x00);
    }
    if (!vm->strict_bdos) {
        ram_write8(vm, (uint16_t)(fcb_addr + 32), 0x00);
    }
    return 0x0000;
}

static uint16_t bdos_delete(CpmVm *vm, uint16_t fcb_addr) {
    uint8_t drive = 0;
    uint8_t pat[11];
    char dir_path[1100];
    DIR *dp;
    struct dirent *de;
    bool deleted_any = false;

    if (!fcb_extract_83(vm, fcb_addr, &drive, pat, NULL, 0)) {
        return 0x00FF;
    }
    if (vm->ro_vec & (1U << drive)) return 0x00FF;
    if (!resolve_drive_dir(vm, drive, dir_path, sizeof(dir_path), false)) {
        return 0x00FF;
    }

    dp = opendir(dir_path);
    if (!dp) return 0x00FF;
    while ((de = readdir(dp)) != NULL) {
        uint8_t cpm11[11];
        char full[1400];
        struct stat st;
        if (!host_name_to_83(de->d_name, cpm11)) continue;
        if (!match_83(cpm11, pat)) continue;
        snprintf(full, sizeof(full), "%s/%s", dir_path, de->d_name);
        if (stat(full, &st) == 0 && S_ISREG(st.st_mode)) {
            if (unlink(full) == 0) {
                open_fcb_clear_file(vm, drive, cpm11);
                deleted_any = true;
            }
        }
    }
    closedir(dp);
    return deleted_any ? 0x0000 : 0x00FF;
}

static uint16_t bdos_rename(CpmVm *vm, uint16_t fcb_addr) {
    char old_path[1400], new_path[1400], existing_target[1400];
    uint8_t drive = 0, old_drive = 0;
    uint8_t old_pat[11], new_pat[11];
    char new_upper[32], dir_path[1100];
    uint8_t old_dr = ram_read8(vm, fcb_addr);

    if (!fcb_extract_83(vm, fcb_addr, &old_drive, old_pat, NULL, 0)) {
        return 0x00FF;
    }
    if (!resolve_existing_file(vm, fcb_addr, old_path, sizeof(old_path), &drive)) {
        return 0x00FF;
    }
    if (vm->ro_vec & (1U << drive)) return 0x00FF;

    /* Force second FCB to use same drive as first FCB */
    ram_write8(vm, (uint16_t)(fcb_addr + 16), old_dr);
    if (!fcb_extract_83(vm, (uint16_t)(fcb_addr + 16), &drive, new_pat, new_upper, sizeof(new_upper))) {
        return 0x00FF;
    }
    if (memchr(new_pat, '?', 11) != NULL) return 0x00FF;
    if (vm->strict_bdos &&
        resolve_existing_file(vm, (uint16_t)(fcb_addr + 16), existing_target, sizeof(existing_target), &drive)) {
        return 0x00FF;
    }
    if (!resolve_drive_dir(vm, drive, dir_path, sizeof(dir_path), false)) {
        return 0x00FF;
    }
    snprintf(new_path, sizeof(new_path), "%s/%s", dir_path, new_upper);
    if (rename(old_path, new_path) == 0) {
        open_fcb_clear_file(vm, old_drive, old_pat);
        return 0x0000;
    }
    return 0x00FF;
}

static uint32_t fcb_seq_record(const CpmVm *vm, uint16_t fcb_addr) {
    uint32_t cr = ram_read8(vm, (uint16_t)(fcb_addr + 32)) & 0x7FU;
    uint32_t ex = ram_read8(vm, (uint16_t)(fcb_addr + 12)) & 0x1FU;
    uint32_t s2 = ram_read8(vm, (uint16_t)(fcb_addr + 14)) & 0x0FU;
    return (s2 << 12) | (ex << 7) | cr;
}

static uint16_t bdos_read_seq(CpmVm *vm, uint16_t fcb_addr) {
    char path[1400];
    uint8_t drive = 0;
    FILE *fp;
    uint32_t rec;
    long fpos;
    uint8_t buf[128];
    size_t nread;
    int i;

    if (!check_fcb_open(vm, fcb_addr)) {
        return 0x00FF;
    }
    if (!resolve_existing_file(vm, fcb_addr, path, sizeof(path), &drive)) {
        return 0x00FF;
    }
    rec = fcb_seq_record(vm, fcb_addr);
    fpos = (long)rec * 128L;
    fp = fopen(path, "rb");
    if (!fp) return 0x00FF;
    if (fseek(fp, fpos, SEEK_SET) != 0) {
        fclose(fp);
        return 0x0001;
    }
    memset(buf, 0x1A, sizeof(buf));
    nread = fread(buf, 1, 128, fp);
    fclose(fp);
    if (nread == 0) {
        return 0x0001; /* EOF */
    }
    for (i = 0; i < 128; i++) {
        ram_write8(vm, (uint16_t)(vm->dma_addr + i), buf[i]);
    }
    {
        uint8_t cr = (uint8_t)((ram_read8(vm, (uint16_t)(fcb_addr + 32)) & 0x7FU) + 1U);
        uint8_t ex = ram_read8(vm, (uint16_t)(fcb_addr + 12)) & 0x1FU;
        uint8_t s2 = ram_read8(vm, (uint16_t)(fcb_addr + 14));
        if (cr >= 128) {
            cr = 0;
            ex++;
            if (ex > 31) {
                ex = 0;
                s2 = (uint8_t)((s2 & 0x80) | (((s2 & 0x0F) + 1) & 0x0F));
            }
        }
        ram_write8(vm, (uint16_t)(fcb_addr + 32), cr);
        ram_write8(vm, (uint16_t)(fcb_addr + 12), ex);
        ram_write8(vm, (uint16_t)(fcb_addr + 14), s2);
    }
    return 0x0000;
}

static uint16_t write_record_at(CpmVm *vm, const char *path, long fpos) {
    FILE *fp;
    struct stat st;
    uint8_t buf[128];
    int i;
    if (stat(path, &st) != 0) return 0x00FF;
    fp = fopen(path, "r+b");
    if (!fp) return 0x00FF;
    if ((long)st.st_size < fpos) {
        static const uint8_t zeros[128] = {0};
        long cur = (long)st.st_size;
        if (fseek(fp, 0, SEEK_END) != 0) {
            fclose(fp);
            return 0x00FF;
        }
        while (cur < fpos) {
            long chunk = fpos - cur;
            if (chunk > 128) chunk = 128;
            if (fwrite(zeros, 1, (size_t)chunk, fp) != (size_t)chunk) {
                fclose(fp);
                return 0x00FF;
            }
            cur += chunk;
        }
    }
    if (fseek(fp, fpos, SEEK_SET) != 0) {
        fclose(fp);
        return 0x00FF;
    }
    for (i = 0; i < 128; i++) {
        buf[i] = ram_read8(vm, (uint16_t)(vm->dma_addr + i));
    }
    if (fwrite(buf, 1, 128, fp) != 128) {
        fclose(fp);
        return 0x00FF;
    }
    fclose(fp);
    return 0x0000;
}

static uint16_t bdos_write_seq(CpmVm *vm, uint16_t fcb_addr) {
    char path[1400];
    uint8_t drive = 0;
    uint32_t rec;
    uint16_t res;

    if (!check_fcb_open(vm, fcb_addr)) {
        return 0x00FF;
    }
    if (!resolve_existing_file(vm, fcb_addr, path, sizeof(path), &drive)) {
        return 0x00FF;
    }
    if (vm->ro_vec & (1U << drive)) return 0x00FF;
    rec = fcb_seq_record(vm, fcb_addr);
    if (rec >= 65536U) return 0x0002;
    res = write_record_at(vm, path, (long)rec * 128L);
    if (res != 0) return res;

    {
        uint8_t cr = (uint8_t)((ram_read8(vm, (uint16_t)(fcb_addr + 32)) & 0x7FU) + 1U);
        uint8_t ex = ram_read8(vm, (uint16_t)(fcb_addr + 12)) & 0x1FU;
        uint8_t s2 = (uint8_t)(ram_read8(vm, (uint16_t)(fcb_addr + 14)) & 0x7FU);
        uint8_t rc = ram_read8(vm, (uint16_t)(fcb_addr + 15));
        if (cr >= 128) {
            cr = 0;
            ex++;
            rc = 0;
            if (ex > 31) {
                ex = 0;
                s2 = (uint8_t)((s2 + 1) & 0x0F);
            }
        } else {
            if (rc < cr) rc = cr;
        }
        ram_write8(vm, (uint16_t)(fcb_addr + 32), cr);
        ram_write8(vm, (uint16_t)(fcb_addr + 12), ex);
        ram_write8(vm, (uint16_t)(fcb_addr + 14), s2);
        ram_write8(vm, (uint16_t)(fcb_addr + 15), rc);
    }
    return 0x0000;
}

static uint16_t bdos_read_rand(CpmVm *vm, uint16_t fcb_addr) {
    char path[1400];
    uint8_t drive = 0;
    uint32_t rec;
    long fpos;
    long fsize;
    FILE *fp;
    uint8_t buf[128];
    size_t nread;
    int i;

    if (!check_fcb_open(vm, fcb_addr)) {
        return 0x00FF;
    }
    if (!resolve_existing_file(vm, fcb_addr, path, sizeof(path), &drive)) {
        return 0x00FF;
    }
    rec = (uint32_t)ram_read8(vm, (uint16_t)(fcb_addr + 33)) |
          ((uint32_t)ram_read8(vm, (uint16_t)(fcb_addr + 34)) << 8) |
          ((uint32_t)ram_read8(vm, (uint16_t)(fcb_addr + 35)) << 16);
    if (rec >= 65536U) {
        return 0x0006;
    }

    ram_write8(vm, (uint16_t)(fcb_addr + 32), (uint8_t)(rec & 0x7FU));
    ram_write8(vm, (uint16_t)(fcb_addr + 12), (uint8_t)((rec >> 7) & 0x1FU));
    ram_write8(vm, (uint16_t)(fcb_addr + 14),
               (uint8_t)(((rec >> 12) & 0x0FU) | (ram_read8(vm, (uint16_t)(fcb_addr + 14)) & 0x80U)));

    fsize = get_file_size(path);
    if (fsize < 0) return 0x00FF;
    fpos = (long)rec * 128L;
    if (fpos >= fsize) {
        long ext_size = ((fsize + 16383L) / 16384L) * 16384L;
        return (fpos < ext_size) ? 0x0001 : 0x0004;
    }

    fp = fopen(path, "rb");
    if (!fp) return 0x00FF;
    if (fseek(fp, fpos, SEEK_SET) != 0) {
        fclose(fp);
        return 0x0001;
    }
    memset(buf, 0x1A, sizeof(buf));
    nread = fread(buf, 1, 128, fp);
    fclose(fp);
    if (nread == 0) return 0x0001;
    for (i = 0; i < 128; i++) {
        ram_write8(vm, (uint16_t)(vm->dma_addr + i), buf[i]);
    }
    return 0x0000;
}

static uint16_t bdos_write_rand(CpmVm *vm, uint16_t fcb_addr) {
    char path[1400];
    uint8_t drive = 0;
    uint32_t rec;
    uint16_t res;

    if (!check_fcb_open(vm, fcb_addr)) {
        return 0x00FF;
    }
    if (!resolve_existing_file(vm, fcb_addr, path, sizeof(path), &drive)) {
        return 0x00FF;
    }
    if (vm->ro_vec & (1U << drive)) return 0x00FF;
    rec = (uint32_t)ram_read8(vm, (uint16_t)(fcb_addr + 33)) |
          ((uint32_t)ram_read8(vm, (uint16_t)(fcb_addr + 34)) << 8) |
          ((uint32_t)ram_read8(vm, (uint16_t)(fcb_addr + 35)) << 16);
    if (rec >= 65536U) {
        return 0x0006;
    }
    res = write_record_at(vm, path, (long)rec * 128L);
    if (res != 0) return res;

    ram_write8(vm, (uint16_t)(fcb_addr + 32), (uint8_t)(rec & 0x7FU));
    ram_write8(vm, (uint16_t)(fcb_addr + 12), (uint8_t)((rec >> 7) & 0x1FU));
    ram_write8(vm, (uint16_t)(fcb_addr + 14), (uint8_t)((rec >> 12) & 0x0FU));
    return 0x0000;
}

static uint16_t bdos_file_size(CpmVm *vm, uint16_t fcb_addr) {
    char path[1400];
    uint8_t drive = 0;
    long fsize;
    uint32_t recs;
    if (!resolve_existing_file(vm, fcb_addr, path, sizeof(path), &drive)) {
        return 0x00FF;
    }
    fsize = get_file_size(path);
    if (fsize < 0) return 0x00FF;
    recs = (uint32_t)((fsize + 127L) / 128L);
    ram_write8(vm, (uint16_t)(fcb_addr + 33), (uint8_t)(recs & 0xFF));
    ram_write8(vm, (uint16_t)(fcb_addr + 34), (uint8_t)((recs >> 8) & 0xFF));
    ram_write8(vm, (uint16_t)(fcb_addr + 35), (uint8_t)((recs >> 16) & 0xFF));
    return 0x0000;
}

static uint16_t bdos_set_rand_rec(CpmVm *vm, uint16_t fcb_addr) {
    uint32_t rec = fcb_seq_record(vm, fcb_addr);
    ram_write8(vm, (uint16_t)(fcb_addr + 33), (uint8_t)(rec & 0xFF));
    ram_write8(vm, (uint16_t)(fcb_addr + 34), (uint8_t)((rec >> 8) & 0xFF));
    ram_write8(vm, (uint16_t)(fcb_addr + 35), (uint8_t)((rec >> 16) & 0xFF));
    return 0x0000;
}

static const char *parse_token_to_fcb(CpmVm *vm, uint16_t fcb_addr, const char *p) {
    int i;
    char token[64];
    int tlen = 0;
    const char *s;

    memset(&vm->ram[fcb_addr], 0, 16);
    memset(&vm->ram[fcb_addr + 1], ' ', 11);

    while (*p == ' ' || *p == '\t') p++;
    if (*p == '\0') return p;

    while (*p && *p != ' ' && *p != '\t' && tlen < (int)sizeof(token) - 1) {
        token[tlen++] = (char)toupper((unsigned char)*p++);
    }
    token[tlen] = '\0';

    s = token;
    if (tlen >= 2 && s[1] == ':' && s[0] >= 'A' && s[0] <= 'P') {
        vm->ram[fcb_addr] = (uint8_t)(s[0] - 'A' + 1);
        s += 2;
    }

    i = 0;
    while (*s && *s != '.' && i < 8) {
        if (*s == '*') {
            while (i < 8) vm->ram[fcb_addr + 1 + i++] = '?';
            while (*s && *s != '.') s++;
            break;
        }
        vm->ram[fcb_addr + 1 + i++] = (uint8_t)*s++;
    }
    while (*s && *s != '.') s++;
    if (*s == '.') {
        s++;
        i = 0;
        while (*s && i < 3) {
            if (*s == '*') {
                while (i < 3) vm->ram[fcb_addr + 9 + i++] = '?';
                break;
            }
            vm->ram[fcb_addr + 9 + i++] = (uint8_t)*s++;
        }
    }
    return p;
}

void cpm_setup_page_zero(CpmVm *vm) {
    uint16_t bios_wboot;
    uint16_t sp_init;
    uint16_t max_bios;
    uint16_t i;
    char tail_buf[128];
    size_t tail_len = 0;
    const char *tok_ptr;

    if (vm->tpa_top < 0x0200) vm->tpa_top = 0x0200;
    if (vm->tpa_top > 0xFE00) vm->tpa_top = 0xFE00;
    vm->bdos_entry = vm->tpa_top;
    vm->bios_base = 0xFF00;
    bios_wboot = (uint16_t)(vm->bios_base + 3);
    max_bios = 33;

    /* Page zero vectors */
    memset(&vm->ram[0x0000], 0, 256);
    vm->ram[0x0000] = 0xC3;
    ram_write16(vm, 0x0001, bios_wboot);
    vm->ram[0x0003] = 0x00;
    vm->ram[0x0004] = (uint8_t)(((vm->user_code & 0x0F) << 4) | (vm->cur_drive & 0x0F));
    vm->ram[0x0005] = 0xC3;
    ram_write16(vm, 0x0006, vm->bdos_entry);

    /* BDOS & BIOS RET stubs */
    vm->ram[vm->bdos_entry] = 0xC9;
    for (i = 0; i < max_bios; i++) {
        vm->ram[(uint16_t)(vm->bios_base + i * 3)] = 0xC9;
    }

    /* CLI tail at $0080 and FCB1/FCB2 at $005C/$006C */
    memset(tail_buf, 0, sizeof(tail_buf));
    if (vm->cli_tail[0] != '\0') {
        if (vm->raw_tail || vm->cli_tail[0] == ' ') {
            snprintf(tail_buf, sizeof(tail_buf), "%s", vm->cli_tail);
        } else {
            snprintf(tail_buf, sizeof(tail_buf), " %s", vm->cli_tail);
        }
        tail_len = strlen(tail_buf);
        if (tail_len > 126) tail_len = 126;
        if (!vm->raw_tail) {
            for (i = 0; i < tail_len; i++) {
                tail_buf[i] = (char)toupper((unsigned char)tail_buf[i]);
            }
        }
        vm->ram[0x0080] = (uint8_t)tail_len;
        memcpy(&vm->ram[0x0081], tail_buf, tail_len);
        vm->ram[0x0081 + tail_len] = 0x00;

        tok_ptr = parse_token_to_fcb(vm, 0x005C, tail_buf);
        parse_token_to_fcb(vm, 0x006C, tok_ptr);
    } else {
        parse_token_to_fcb(vm, 0x005C, "");
        parse_token_to_fcb(vm, 0x006C, "");
    }

    /* Initial CPU registers & stack */
    sp_init = (uint16_t)(vm->tpa_top - 2);
    ram_write16(vm, sp_init, 0x0000);
    vm->pc = 0x0100;
    vm->sp = sp_init;
    vm->af = 0;
    vm->bc = vm->ram[0x0004];
    vm->de = 0;
    vm->hl = 0;
    vm->ix = 0;
    vm->iy = 0;
    vm->af1 = vm->bc1 = vm->de1 = vm->hl1 = 0;
    vm->iff = 0;
    vm->ir = 0;
    vm->dma_addr = 0x0080;
    open_fcb_clear_all(vm);
    vm->stdin_eof = false;
    vm->readstr_active = false;
    vm->idle_polls = 0;
    vm->status = CPM_RUNNING;
    vm->exit_code = 0;
    vm->exit_reason[0] = '\0';
}

bool cpm_load_com(CpmVm *vm, const char *path, char *err_buf, size_t err_cap) {
    FILE *fp;
    long fsize;
    size_t nread;

    memset(vm->ram, 0, sizeof(vm->ram));
    fp = fopen(path, "rb");
    if (!fp) {
        snprintf(err_buf, err_cap, "cannot open COM file '%s': %s", path, strerror(errno));
        return false;
    }
    if (fseek(fp, 0, SEEK_END) != 0 || (fsize = ftell(fp)) < 0 || fseek(fp, 0, SEEK_SET) != 0) {
        fclose(fp);
        snprintf(err_buf, err_cap, "cannot stat COM file '%s'", path);
        return false;
    }

    /* Setup page zero before checking limits so bios_base/tpa_top are resolved */
    cpm_setup_page_zero(vm);

    if (fsize > (long)(vm->bios_base - 0x0100)) {
        fclose(fp);
        snprintf(err_buf, err_cap, "COM file '%s' (%ld bytes) exceeds 64K address space before BIOS ($%04X)",
                 path, fsize, vm->bios_base);
        return false;
    }
    if (vm->strict_tpa && fsize > (long)(vm->tpa_top - 0x0100)) {
        fclose(fp);
        snprintf(err_buf, err_cap, "COM file '%s' (%ld bytes) exceeds TPA top ($%04X)",
                 path, fsize, vm->tpa_top);
        return false;
    }

    if (fsize > 0) {
        nread = fread(&vm->ram[0x0100], 1, (size_t)fsize, fp);
        if (nread != (size_t)fsize) {
            fclose(fp);
            snprintf(err_buf, err_cap, "short read loading '%s'", path);
            return false;
        }
    }
    fclose(fp);
    snprintf(vm->com_path, sizeof(vm->com_path), "%s", path);

    /* Ensure BDOS/BIOS stubs aren't overwritten if strict_tpa wasn't set */
    vm->ram[vm->bdos_entry] = 0xC9;
    return true;
}

static void bdos_set_ret(CpmVm *vm, uint16_t hl_ret) {
    vm->hl = hl_ret;
    vm->af = (vm->af & 0x00FFU) | ((hl_ret & 0x00FFU) << 8);
    vm->bc = (vm->bc & 0x00FFU) | (hl_ret & 0xFF00U);
}

bool bdos_call(CpmVm *vm) {
    uint8_t fn = (uint8_t)(vm->bc & 0xFFU);
    uint16_t de = (uint16_t)(vm->de & 0xFFFFU);
    uint8_t e = (uint8_t)(de & 0xFFU);
    uint16_t hl_ret = 0x0000;

    if (vm->strict_bdos) {
        uint16_t k;
        if (vm->sp < 0x0128U) {
            vm->status = CPM_FAULT;
            vm->exit_code = 1;
            snprintf(vm->exit_reason, sizeof(vm->exit_reason), "bdos_stack_underflow");
            return false;
        }
        for (k = 1; k <= 32U; k++) {
            vm->ram[(uint16_t)(vm->sp - k)] = 0xCCU;
        }
    }

    switch (fn) {
    case 0: /* P_TERMCPM */
        vm->status = CPM_EXITED;
        vm->exit_code = 0;
        snprintf(vm->exit_reason, sizeof(vm->exit_reason), "bdos_0");
        return false;

    case 1: { /* C_READ */
        uint8_t ch = 0;
        vm->idle_polls = 0;
        if (!cpm_read_input_blocking(vm, &ch, NULL)) {
            return false;
        }
        cpm_emit_char(vm, ch);
        hl_ret = ch;
        break;
    }

    case 2: /* C_WRITE */
        vm->idle_polls = 0;
        cpm_emit_char(vm, e);
        break;

    case 6: { /* C_RAWIO: strict CP/M 2.2 semantics */
        if (e == 0xFF) {
            uint8_t ch = 0;
            if (cpm_read_input_nonblock(vm, &ch)) {
                vm->idle_polls = 0;
                hl_ret = ch;
            } else {
                vm->idle_polls++;
                hl_ret = 0x0000;
                if (vm->stop_on_idle && vm->idle_polls >= vm->idle_poll_threshold) {
                    vm->status = CPM_IDLE;
                }
            }
        } else {
            vm->idle_polls = 0;
            cpm_emit_char(vm, e);
        }
        break;
    }

    case 7: /* A_STATIN / Get IOBYTE */
        hl_ret = ram_read8(vm, 0x0003);
        break;

    case 8: /* A_STATOUT / Set IOBYTE */
        ram_write8(vm, 0x0003, e);
        break;

    case 9: { /* C_WRITESTR */
        uint16_t addr = de;
        uint32_t count = 0;
        uint8_t ch;
        vm->idle_polls = 0;
        while (count < 65536U) {
            ch = ram_read8(vm, addr++);
            if (ch == '$') {
                break;
            }
            cpm_emit_char(vm, ch);
            count++;
        }
        if (count == 65536U) {
            vm->status = CPM_FAULT;
            vm->exit_code = 1;
            snprintf(vm->exit_reason, sizeof(vm->exit_reason), "bdos_9_unterminated");
            return false;
        }
        break;
    }

    case 10: { /* C_READSTR */
        vm->idle_polls = 0;
        if (!vm->readstr_active) {
            vm->readstr_active = true;
            vm->readstr_buf = de;
            vm->readstr_max = ram_read8(vm, de);
            vm->readstr_cnt = 0;
        }
        for (;;) {
            uint8_t ch = 0;
            bool is_eof = false;
            if (!cpm_read_input_nonblock(vm, &ch)) {
                if (vm->stop_on_wait_input) {
                    vm->status = CPM_WAIT_INPUT;
                    return false;
                }
                if (!cpm_read_input_blocking(vm, &ch, &is_eof)) {
                    return false;
                }
                if (is_eof) {
                    break;
                }
            }
            if (ch == '\r' || ch == '\n') {
                cpm_emit_char(vm, '\r');
                break;
            }
            if (ch == 0x08 || ch == 0x7F) {
                if (vm->readstr_cnt > 0) {
                    vm->readstr_cnt--;
                    cpm_emit_str(vm, "\b \b");
                }
                continue;
            }
            if (ch == 0x03 && vm->readstr_cnt == 0) {
                cpm_emit_str(vm, "^C");
                vm->readstr_active = false;
                vm->status = CPM_EXITED;
                vm->exit_code = 0;
                snprintf(vm->exit_reason, sizeof(vm->exit_reason), "ctrl_c");
                return false;
            }
            if ((ch >= 0x20 && ch <= 0x7E) || ch == 0x1A) {
                if (vm->readstr_cnt < vm->readstr_max) {
                    ram_write8(vm, (uint16_t)(vm->readstr_buf + 2 + vm->readstr_cnt), ch);
                    vm->readstr_cnt++;
                    cpm_emit_char(vm, ch);
                }
            }
        }
        ram_write8(vm, (uint16_t)(vm->readstr_buf + 1), vm->readstr_cnt);
        hl_ret = vm->readstr_cnt;
        vm->readstr_active = false;
        break;
    }

    case 11: /* C_STAT */
        if (cpm_input_available(vm)) {
            vm->idle_polls = 0;
            hl_ret = 0x00FF;
        } else {
            vm->idle_polls++;
            hl_ret = 0x0000;
            if (vm->stop_on_idle && vm->idle_polls >= vm->idle_poll_threshold) {
                vm->status = CPM_IDLE;
            }
        }
        break;

    case 12: /* S_BDOSVER */
        hl_ret = 0x0022;
        break;

    case 13: /* DRV_ALLRESET */
        vm->idle_polls = 0;
        vm->ro_vec = 0;
        vm->login_vec = 0;
        vm->dma_addr = 0x0080;
        vm->cur_drive = 0;
        open_fcb_clear_all(vm);
        ram_write8(vm, 0x0004, (uint8_t)((vm->user_code & 0x0F) << 4));
        hl_ret = 0x0000;
        break;

    case 14: { /* DRV_SET */
        char dir_path[1024];
        vm->idle_polls = 0;
        if (e < 16 && resolve_drive_dir(vm, e, dir_path, sizeof(dir_path), false)) {
            vm->cur_drive = e;
            vm->login_vec |= (uint16_t)(1U << e);
            ram_write8(vm, 0x0004, (uint8_t)(((vm->user_code & 0x0F) << 4) | (vm->cur_drive & 0x0F)));
            hl_ret = 0x0000;
        } else if (vm->strict_bdos) {
            char err_msg[48];
            char dch = (e < 16) ? (char)('A' + e) : '?';
            snprintf(err_msg, sizeof(err_msg), "\r\nBdos Err on %c: Select\r\n", dch);
            cpm_emit_str(vm, err_msg);
            vm->status = CPM_EXITED;
            vm->exit_code = 1;
            snprintf(vm->exit_reason, sizeof(vm->exit_reason), "bdos_select_err");
            return false;
        } else {
            hl_ret = 0x01FF; /* A=0xFF, B/H=1 select error (--no-strict-bdos) */
        }
        break;
    }

    case 15: /* F_OPEN */
        vm->idle_polls = 0;
        hl_ret = bdos_open(vm, de);
        break;

    case 16: /* F_CLOSE */
        vm->idle_polls = 0;
        hl_ret = bdos_close(vm, de);
        break;

    case 17: /* F_SFIRST */
        vm->idle_polls = 0;
        hl_ret = bdos_search_first(vm, de);
        break;

    case 18: /* F_SNEXT */
        vm->idle_polls = 0;
        hl_ret = bdos_search_next(vm);
        break;

    case 19: /* F_DELETE */
        vm->idle_polls = 0;
        hl_ret = bdos_delete(vm, de);
        break;

    case 20: /* F_READ */
        vm->idle_polls = 0;
        hl_ret = bdos_read_seq(vm, de);
        break;

    case 21: /* F_WRITE */
        vm->idle_polls = 0;
        hl_ret = bdos_write_seq(vm, de);
        break;

    case 22: /* F_MAKE */
        vm->idle_polls = 0;
        hl_ret = bdos_make(vm, de);
        break;

    case 23: /* F_RENAME */
        vm->idle_polls = 0;
        hl_ret = bdos_rename(vm, de);
        break;

    case 24: /* DRV_LOGINVEC */
        hl_ret = vm->login_vec;
        break;

    case 25: /* DRV_GET */
        hl_ret = vm->cur_drive;
        break;

    case 26: /* F_DMAOFF */
        vm->dma_addr = de;
        break;

    case 28: /* DRV_SETRO */
        vm->ro_vec |= (uint16_t)(1U << vm->cur_drive);
        break;

    case 29: /* DRV_ROVEC */
        hl_ret = vm->ro_vec;
        break;

    case 30: /* F_ATTRIB */
        hl_ret = 0x0000;
        break;

    case 32: /* F_USERNUM */
        if (e == 0xFF) {
            hl_ret = vm->user_code;
        } else {
            vm->user_code = e & 0x0F;
            ram_write8(vm, 0x0004, (uint8_t)(((vm->user_code & 0x0F) << 4) | (vm->cur_drive & 0x0F)));
            hl_ret = vm->user_code;
        }
        break;

    case 33: /* F_READRAND */
        vm->idle_polls = 0;
        hl_ret = bdos_read_rand(vm, de);
        break;

    case 34: /* F_WRITERAND */
    case 40: /* F_WRITEZF */
        vm->idle_polls = 0;
        hl_ret = bdos_write_rand(vm, de);
        break;

    case 35: /* F_SIZE */
        vm->idle_polls = 0;
        hl_ret = bdos_file_size(vm, de);
        break;

    case 36: /* F_RANDREC */
        hl_ret = bdos_set_rand_rec(vm, de);
        break;

    case 37: /* DRV_RESET */
        vm->ro_vec &= (uint16_t)~de;
        hl_ret = 0x0000;
        break;

    default:
        hl_ret = 0x0000;
        break;
    }

    bdos_set_ret(vm, hl_ret);
    if (vm->strict_bdos) {
        vm->af = (vm->af & 0xFF00U) | 0x00FFU;
        vm->bc = (vm->bc & 0xFF00U) | 0x00FFU;
        vm->de = 0xDEADU;
        vm->ix = 0xBEEFU;
        vm->iy = 0xCAFEU;
    }
    return true;
}

bool bios_call(CpmVm *vm, uint8_t func_index) {
    uint8_t c = (uint8_t)(vm->bc & 0xFFU);
    switch (func_index) {
    case 0: /* BOOT */
    case 1: /* WBOOT */
        vm->status = CPM_EXITED;
        vm->exit_code = 0;
        snprintf(vm->exit_reason, sizeof(vm->exit_reason),
                 func_index == 0 ? "bios_boot" : "warm_boot");
        return false;

    case 2: /* CONST */
        if (cpm_input_available(vm)) {
            vm->idle_polls = 0;
            vm->af = (vm->af & 0x00FFU) | 0xFF00U;
        } else {
            vm->idle_polls++;
            vm->af = (vm->af & 0x00FFU);
            if (vm->stop_on_idle && vm->idle_polls >= vm->idle_poll_threshold) {
                vm->status = CPM_IDLE;
            }
        }
        break;

    case 3: { /* CONIN */
        uint8_t ch = 0;
        vm->idle_polls = 0;
        if (!cpm_read_input_blocking(vm, &ch, NULL)) {
            return false;
        }
        vm->af = (vm->af & 0x00FFU) | ((uint32_t)ch << 8);
        break;
    }

    case 4: /* CONOUT */
        vm->idle_polls = 0;
        cpm_emit_char(vm, c);
        break;

    case 9: { /* SELDSK: HL = non-zero DPH if mounted, 0x0000 if unmounted/invalid */
        char dir_path[1024];
        vm->idle_polls = 0;
        if (c < 16 && resolve_drive_dir(vm, c, dir_path, sizeof(dir_path), false)) {
            vm->hl = (uint16_t)(0xFF80U + ((uint16_t)c * 8U));
        } else {
            vm->hl = 0x0000U;
        }
        if (vm->strict_bdos) {
            vm->af = 0x5A00U;
            vm->bc = 0xDEADU;
            vm->de = 0xBEEFU;
            vm->ix = 0x1234U;
            vm->iy = 0x5678U;
        }
        break;
    }

    case 12: /* SETDMA */
        vm->dma_addr = (uint16_t)(vm->bc & 0xFFFFU);
        vm->hl = vm->dma_addr;
        break;

    case 15: /* LISTST */
    case 17: /* CONOST */
        vm->af = (vm->af & 0x00FFU) | 0xFF00U;
        break;

    case 16: /* SECTRAN */
        vm->hl = vm->bc & 0xFFFFU;
        break;

    default:
        break;
    }
    return true;
}

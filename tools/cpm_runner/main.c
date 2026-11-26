#define _POSIX_C_SOURCE 200809L
#include "ansi.h"
#include "bdos.h"
#include "json.h"
#include "vm.h"
#include "z80.h"

#include <ctype.h>
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <termios.h>
#include <unistd.h>

static bool g_tty_raw = false;
static struct termios g_orig_termios;
static volatile sig_atomic_t g_stop_signal = 0;
static volatile int g_stop_flag = 0;

static void restore_tty(void) {
    if (g_tty_raw) {
        tcsetattr(STDIN_FILENO, TCSANOW, &g_orig_termios);
        g_tty_raw = false;
        if (isatty(STDOUT_FILENO)) {
            static const char reset_seq[] = "\x1b[0m\x1b[?25h\r\n";
            ssize_t unused = write(STDOUT_FILENO, reset_seq, sizeof(reset_seq) - 1);
            (void)unused;
        }
    }
}

static void on_signal(int sig) {
    g_stop_signal = sig;
    g_stop_flag = 1;
}

static bool parse_u64(const char *s, uint64_t *out) {
    char *endp = NULL;
    int base = 10;
    unsigned long long v;
    if (!s || !*s) return false;
    if (s[0] == '$') {
        s++;
        base = 16;
    } else if (s[0] == '0' && (s[1] == 'x' || s[1] == 'X')) {
        base = 16;
    }
    v = strtoull(s, &endp, base);
    if (endp == s || *endp != '\0') return false;
    *out = (uint64_t)v;
    return true;
}

static bool parse_u16(const char *s, uint16_t *out) {
    uint64_t v = 0;
    if (!parse_u64(s, &v) || v > 0xFFFFULL) return false;
    *out = (uint16_t)v;
    return true;
}

static void emit_id_prefix(FILE *fp, const JVal *req) {
    const JVal *id = json_obj_get(req, "id");
    if (!id) return;
    if (id->type == JVAL_INT) {
        fprintf(fp, "\"id\":%lld,", (long long)id->u.i);
    } else if (id->type == JVAL_STR) {
        fputs("\"id\":", fp);
        json_emit_str(fp, id->u.s.ptr, id->u.s.len);
        fputc(',', fp);
    }
}

static void emit_err(const JVal *req, const char *msg) {
    fputc('{', stdout);
    emit_id_prefix(stdout, req);
    fputs("\"ok\":false,\"error\":", stdout);
    json_emit_str(stdout, msg, strlen(msg));
    fputs("}\n", stdout);
    fflush(stdout);
}

static void emit_regs_fields(FILE *fp, const CpmVm *vm) {
    fprintf(fp,
            "\"pc\":%u,\"sp\":%u,\"af\":%u,\"bc\":%u,\"de\":%u,\"hl\":%u,"
            "\"ix\":%u,\"iy\":%u,\"af_alt\":%u,\"bc_alt\":%u,\"de_alt\":%u,\"hl_alt\":%u,"
            "\"i\":%u,\"r\":%u,\"iff\":%u,\"steps\":%llu,\"status\":",
            (unsigned)(vm->pc & 0xFFFFU),
            (unsigned)(vm->sp & 0xFFFFU),
            (unsigned)(vm->af & 0xFFFFU),
            (unsigned)(vm->bc & 0xFFFFU),
            (unsigned)(vm->de & 0xFFFFU),
            (unsigned)(vm->hl & 0xFFFFU),
            (unsigned)(vm->ix & 0xFFFFU),
            (unsigned)(vm->iy & 0xFFFFU),
            (unsigned)(vm->af1 & 0xFFFFU),
            (unsigned)(vm->bc1 & 0xFFFFU),
            (unsigned)(vm->de1 & 0xFFFFU),
            (unsigned)(vm->hl1 & 0xFFFFU),
            (unsigned)((vm->ir >> 8) & 0xFFU),
            (unsigned)(vm->ir & 0xFFU),
            (unsigned)(vm->iff & 0xFFU),
            (unsigned long long)vm->total_steps);
    json_emit_str(fp, cpm_status_name(vm->status), strlen(cpm_status_name(vm->status)));
    fprintf(fp, ",\"exit_code\":%d,\"exit_reason\":", vm->exit_code);
    json_emit_str(fp, vm->exit_reason, strlen(vm->exit_reason));
}

static void emit_run_result(const JVal *req, const CpmVm *vm, uint64_t steps_run) {
    const char *reason = cpm_status_name(vm->status);
    fputc('{', stdout);
    emit_id_prefix(stdout, req);
    fputs("\"ok\":true,\"reason\":", stdout);
    json_emit_str(stdout, reason, strlen(reason));
    fprintf(stdout, ",\"steps_run\":%llu,", (unsigned long long)steps_run);
    emit_regs_fields(stdout, vm);
    fprintf(stdout, ",\"idle_polls\":%u,\"console_out_len\":%zu,\"input_queue_len\":%zu}\n",
            vm->idle_polls, vm->out_len, cpm_input_len(vm));
    fflush(stdout);
}

static int run_control_loop(CpmVm *vm) {
    char *line = NULL;
    size_t line_cap = 0;
    ssize_t nread;

    vm->echo_stdout = false;
    vm->stop_on_wait_input = true;

    while ((nread = getline(&line, &line_cap, stdin)) != -1) {
        char err_buf[256];
        JVal *req;
        const JVal *cmd_val;
        const char *cmd;

        while (nread > 0 && (line[nread - 1] == '\n' || line[nread - 1] == '\r')) {
            line[--nread] = '\0';
        }
        if (nread == 0) continue;

        req = json_parse(line, err_buf, sizeof(err_buf));
        if (!req || req->type != JVAL_OBJ) {
            emit_err(NULL, req ? "request must be a JSON object" : err_buf);
            json_free(req);
            continue;
        }

        cmd_val = json_obj_get(req, "cmd");
        cmd = json_as_str(cmd_val, NULL);
        if (!cmd) {
            emit_err(req, "missing string 'cmd'");
            json_free(req);
            continue;
        }

        if (strcmp(cmd, "ping") == 0) {
            fputc('{', stdout);
            emit_id_prefix(stdout, req);
            fputs("\"ok\":true,\"pong\":true}\n", stdout);
            fflush(stdout);
        } else if (strcmp(cmd, "info") == 0) {
            fputc('{', stdout);
            emit_id_prefix(stdout, req);
            fputs("\"ok\":true,\"com_path\":", stdout);
            json_emit_str(stdout, vm->com_path, strlen(vm->com_path));
            fprintf(stdout,
                    ",\"tpa_top\":%u,\"bdos_entry\":%u,\"bios_base\":%u,\"dma_addr\":%u,"
                    "\"cur_drive\":%u,\"user_code\":%u,",
                    (unsigned)vm->tpa_top, (unsigned)vm->bdos_entry,
                    (unsigned)vm->bios_base, (unsigned)vm->dma_addr,
                    (unsigned)vm->cur_drive, (unsigned)vm->user_code);
            emit_regs_fields(stdout, vm);
            fprintf(stdout, ",\"idle_polls\":%u,\"console_out_len\":%zu,\"input_queue_len\":%zu}\n",
                    vm->idle_polls, vm->out_len, cpm_input_len(vm));
            fflush(stdout);
        } else if (strcmp(cmd, "regs") == 0) {
            fputc('{', stdout);
            emit_id_prefix(stdout, req);
            fputs("\"ok\":true,", stdout);
            emit_regs_fields(stdout, vm);
            fputs("}\n", stdout);
            fflush(stdout);
        } else if (strcmp(cmd, "set_regs") == 0) {
            int64_t val;
            if (json_as_int(json_obj_get(req, "pc"), &val)) vm->pc = (uint32_t)(val & 0xFFFF);
            if (json_as_int(json_obj_get(req, "sp"), &val)) vm->sp = (uint32_t)(val & 0xFFFF);
            if (json_as_int(json_obj_get(req, "af"), &val)) vm->af = (uint32_t)(val & 0xFFFF);
            if (json_as_int(json_obj_get(req, "bc"), &val)) vm->bc = (uint32_t)(val & 0xFFFF);
            if (json_as_int(json_obj_get(req, "de"), &val)) vm->de = (uint32_t)(val & 0xFFFF);
            if (json_as_int(json_obj_get(req, "hl"), &val)) vm->hl = (uint32_t)(val & 0xFFFF);
            if (json_as_int(json_obj_get(req, "ix"), &val)) vm->ix = (uint32_t)(val & 0xFFFF);
            if (json_as_int(json_obj_get(req, "iy"), &val)) vm->iy = (uint32_t)(val & 0xFFFF);
            if (json_as_int(json_obj_get(req, "af_alt"), &val)) vm->af1 = (uint32_t)(val & 0xFFFF);
            if (json_as_int(json_obj_get(req, "bc_alt"), &val)) vm->bc1 = (uint32_t)(val & 0xFFFF);
            if (json_as_int(json_obj_get(req, "de_alt"), &val)) vm->de1 = (uint32_t)(val & 0xFFFF);
            if (json_as_int(json_obj_get(req, "hl_alt"), &val)) vm->hl1 = (uint32_t)(val & 0xFFFF);
            if (json_as_int(json_obj_get(req, "i"), &val)) vm->ir = (vm->ir & 0x00FFU) | (((uint32_t)val & 0xFFU) << 8);
            if (json_as_int(json_obj_get(req, "r"), &val)) vm->ir = (vm->ir & 0xFF00U) | ((uint32_t)val & 0xFFU);
            if (json_as_int(json_obj_get(req, "iff"), &val)) vm->iff = (uint32_t)(val & 0xFF);
            fputc('{', stdout);
            emit_id_prefix(stdout, req);
            fputs("\"ok\":true,", stdout);
            emit_regs_fields(stdout, vm);
            fputs("}\n", stdout);
            fflush(stdout);
        } else if (strcmp(cmd, "read_mem") == 0) {
            int64_t addr = 0, len = 0;
            const char *fmt = json_as_str(json_obj_get(req, "format"), NULL);
            if (!json_as_int(json_obj_get(req, "addr"), &addr) ||
                !json_as_int(json_obj_get(req, "len"), &len) ||
                addr < 0 || len < 0 || addr + len > 65536) {
                emit_err(req, "invalid addr/len for 64KB RAM");
                json_free(req);
                continue;
            }
            fputc('{', stdout);
            emit_id_prefix(stdout, req);
            fprintf(stdout, "\"ok\":true,\"addr\":%lld,\"len\":%lld,", (long long)addr, (long long)len);
            if (fmt && strcmp(fmt, "bytes") == 0) {
                int64_t k;
                fputs("\"bytes\":[", stdout);
                for (k = 0; k < len; k++) {
                    if (k > 0) fputc(',', stdout);
                    fprintf(stdout, "%u", (unsigned)vm->ram[addr + k]);
                }
                fputs("]}\n", stdout);
            } else {
                fputs("\"hex\":", stdout);
                json_emit_hex(stdout, &vm->ram[addr], (size_t)len);
                fputs("}\n", stdout);
            }
            fflush(stdout);
        } else if (strcmp(cmd, "write_mem") == 0) {
            int64_t addr = 0;
            const JVal *hex_v = json_obj_get(req, "hex");
            const JVal *bytes_v = json_obj_get(req, "bytes");
            const JVal *text_v = json_obj_get(req, "text");
            size_t wlen = 0;

            if (!json_as_int(json_obj_get(req, "addr"), &addr) || addr < 0 || addr >= 65536) {
                emit_err(req, "invalid addr for 64KB RAM");
                json_free(req);
                continue;
            }
            if (hex_v) {
                const char *hs = json_as_str(hex_v, NULL);
                if (!hs || !hex_decode(hs, &vm->ram[addr], (size_t)(65536 - addr), &wlen)) {
                    emit_err(req, "invalid or out-of-bounds hex payload");
                    json_free(req);
                    continue;
                }
            } else if (bytes_v && bytes_v->type == JVAL_ARR) {
                size_t k;
                if ((int64_t)bytes_v->u.arr.len + addr > 65536) {
                    emit_err(req, "bytes array exceeds 64KB RAM");
                    json_free(req);
                    continue;
                }
                for (k = 0; k < bytes_v->u.arr.len; k++) {
                    int64_t bv = 0;
                    if (!json_as_int(bytes_v->u.arr.items[k], &bv) || bv < 0 || bv > 255) {
                        emit_err(req, "invalid byte value in bytes array");
                        json_free(req);
                        goto next_line;
                    }
                    vm->ram[addr + (int64_t)k] = (uint8_t)bv;
                }
                wlen = bytes_v->u.arr.len;
            } else if (text_v) {
                size_t tlen = 0;
                const char *ts = json_as_str(text_v, &tlen);
                if (!ts || (int64_t)tlen + addr > 65536) {
                    emit_err(req, "invalid or out-of-bounds text payload");
                    json_free(req);
                    continue;
                }
                memcpy(&vm->ram[addr], ts, tlen);
                wlen = tlen;
            } else {
                emit_err(req, "write_mem requires 'hex', 'bytes', or 'text'");
                json_free(req);
                continue;
            }
            fputc('{', stdout);
            emit_id_prefix(stdout, req);
            fprintf(stdout, "\"ok\":true,\"addr\":%lld,\"len\":%zu}\n", (long long)addr, wlen);
            fflush(stdout);
        } else if (strcmp(cmd, "send_keys") == 0) {
            const JVal *text_v = json_obj_get(req, "text");
            const JVal *hex_v = json_obj_get(req, "hex");
            const JVal *bytes_v = json_obj_get(req, "bytes");
            size_t queued = 0;

            if (text_v) {
                size_t tlen = 0;
                const char *ts = json_as_str(text_v, &tlen);
                if (!ts) {
                    emit_err(req, "'text' must be a string");
                    json_free(req);
                    continue;
                }
                cpm_push_input(vm, (const uint8_t *)ts, tlen);
                queued += tlen;
            }
            if (hex_v) {
                size_t hlen = 0;
                const char *hs = json_as_str(hex_v, &hlen);
                uint8_t *tmp;
                size_t decoded = 0;
                if (!hs) {
                    emit_err(req, "'hex' must be a string");
                    json_free(req);
                    continue;
                }
                tmp = (uint8_t *)malloc(hlen / 2 + 1);
                if (!tmp || !hex_decode(hs, tmp, hlen / 2 + 1, &decoded)) {
                    free(tmp);
                    emit_err(req, "invalid hex payload");
                    json_free(req);
                    continue;
                }
                cpm_push_input(vm, tmp, decoded);
                queued += decoded;
                free(tmp);
            }
            if (bytes_v) {
                size_t k;
                if (bytes_v->type != JVAL_ARR) {
                    emit_err(req, "'bytes' must be an array");
                    json_free(req);
                    continue;
                }
                for (k = 0; k < bytes_v->u.arr.len; k++) {
                    int64_t bv = 0;
                    uint8_t b;
                    if (!json_as_int(bytes_v->u.arr.items[k], &bv) || bv < 0 || bv > 255) {
                        emit_err(req, "invalid byte in 'bytes'");
                        json_free(req);
                        goto next_line;
                    }
                    b = (uint8_t)bv;
                    cpm_push_input(vm, &b, 1);
                    queued++;
                }
            }
            fputc('{', stdout);
            emit_id_prefix(stdout, req);
            fprintf(stdout, "\"ok\":true,\"queued\":%zu,\"input_queue_len\":%zu}\n",
                    queued, cpm_input_len(vm));
            fflush(stdout);
        } else if (strcmp(cmd, "clear_input") == 0) {
            cpm_clear_input(vm);
            fputc('{', stdout);
            emit_id_prefix(stdout, req);
            fputs("\"ok\":true}\n", stdout);
            fflush(stdout);
        } else if (strcmp(cmd, "add_breakpoint") == 0) {
            int64_t addr = 0;
            if (!json_as_int(json_obj_get(req, "addr"), &addr) || addr < 0 || addr > 0xFFFF) {
                emit_err(req, "invalid breakpoint addr");
                json_free(req);
                continue;
            }
            if (vm->num_breakpoints >= sizeof(vm->breakpoints) / sizeof(vm->breakpoints[0])) {
                emit_err(req, "too many breakpoints");
                json_free(req);
                continue;
            }
            vm->breakpoints[vm->num_breakpoints++] = (uint16_t)addr;
            fputc('{', stdout);
            emit_id_prefix(stdout, req);
            fprintf(stdout, "\"ok\":true,\"num_breakpoints\":%zu}\n", vm->num_breakpoints);
            fflush(stdout);
        } else if (strcmp(cmd, "clear_breakpoints") == 0) {
            vm->num_breakpoints = 0;
            fputc('{', stdout);
            emit_id_prefix(stdout, req);
            fputs("\"ok\":true}\n", stdout);
            fflush(stdout);
        } else if (strcmp(cmd, "step") == 0) {
            int64_t count = 1;
            bool stop_idle = false;
            uint64_t start_steps = vm->total_steps;
            json_as_int(json_obj_get(req, "count"), &count);
            json_as_bool(json_obj_get(req, "stop_on_idle"), &stop_idle);
            if (count < 1) count = 1;
            if (vm->status != CPM_EXITED && vm->status != CPM_HALTED && vm->status != CPM_FAULT) {
                vm->status = CPM_RUNNING;
                vm->stop_on_idle = stop_idle;
                vm->idle_polls = 0;
                z80_run(vm, (uint64_t)count);
            }
            emit_run_result(req, vm, vm->total_steps - start_steps);
        } else if (strcmp(cmd, "run_idle") == 0) {
            int64_t max_steps = 5000000;
            int64_t idle_polls = 512;
            uint64_t start_steps = vm->total_steps;
            json_as_int(json_obj_get(req, "max_steps"), &max_steps);
            json_as_int(json_obj_get(req, "idle_polls"), &idle_polls);
            if (max_steps < 0) max_steps = 0;
            if (idle_polls < 1) idle_polls = 1;
            if (vm->status != CPM_EXITED && vm->status != CPM_HALTED && vm->status != CPM_FAULT) {
                vm->status = CPM_RUNNING;
                vm->stop_on_idle = true;
                vm->idle_poll_threshold = (uint32_t)idle_polls;
                vm->idle_polls = 0;
                z80_run(vm, (uint64_t)max_steps);
            }
            emit_run_result(req, vm, vm->total_steps - start_steps);
        } else if (strcmp(cmd, "run") == 0) {
            int64_t max_steps = 50000000;
            uint64_t start_steps = vm->total_steps;
            json_as_int(json_obj_get(req, "max_steps"), &max_steps);
            if (max_steps < 0) max_steps = 0;
            if (vm->status != CPM_EXITED && vm->status != CPM_HALTED && vm->status != CPM_FAULT) {
                vm->status = CPM_RUNNING;
                vm->stop_on_idle = false;
                vm->idle_polls = 0;
                z80_run(vm, (uint64_t)max_steps);
            }
            emit_run_result(req, vm, vm->total_steps - start_steps);
        } else if (strcmp(cmd, "console_out") == 0) {
            int64_t since = 0;
            bool clear = false;
            size_t off, slice_len;
            json_as_int(json_obj_get(req, "since"), &since);
            json_as_bool(json_obj_get(req, "clear"), &clear);
            if (since < 0) since = 0;
            off = (size_t)since;
            if (off > vm->out_len) off = vm->out_len;
            slice_len = vm->out_len - off;

            fputc('{', stdout);
            emit_id_prefix(stdout, req);
            fprintf(stdout, "\"ok\":true,\"offset\":%zu,\"len\":%zu,\"total_len\":%zu,\"text\":",
                    off, slice_len, vm->out_len);
            json_emit_str(stdout, (const char *)(vm->out_buf ? vm->out_buf + off : (const uint8_t *)""), slice_len);
            fputs(",\"hex\":", stdout);
            json_emit_hex(stdout, vm->out_buf ? vm->out_buf + off : (const uint8_t *)"", slice_len);
            fputs("}\n", stdout);
            fflush(stdout);
            if (clear) vm->out_len = 0;
        } else if (strcmp(cmd, "screen") == 0) {
            bool include_attrs = false;
            int r, c;
            char row_buf[ANSI_MAX_COLS + 1];
            json_as_bool(json_obj_get(req, "include_attrs"), &include_attrs);
            fputc('{', stdout);
            emit_id_prefix(stdout, req);
            fprintf(stdout,
                    "\"ok\":true,\"rows\":%d,\"cols\":%d,\"cursor_row\":%d,\"cursor_col\":%d,"
                    "\"cursor_visible\":%s,\"lines\":[",
                    vm->screen.rows, vm->screen.cols,
                    vm->screen.cur_row, vm->screen.cur_col,
                    vm->screen.cursor_visible ? "true" : "false");
            for (r = 0; r < vm->screen.rows; r++) {
                if (r > 0) fputc(',', stdout);
                for (c = 0; c < vm->screen.cols; c++) {
                    uint8_t ch = vm->screen.cells[r * vm->screen.cols + c].ch;
                    row_buf[c] = (ch >= 0x20 && ch < 0x7F) ? (char)ch : ' ';
                }
                json_emit_str(stdout, row_buf, (size_t)vm->screen.cols);
            }
            fputc(']', stdout);
            if (include_attrs) {
                fputs(",\"fg\":[", stdout);
                for (r = 0; r < vm->screen.rows; r++) {
                    if (r > 0) fputc(',', stdout);
                    fputc('[', stdout);
                    for (c = 0; c < vm->screen.cols; c++) {
                        if (c > 0) fputc(',', stdout);
                        fprintf(stdout, "%u", (unsigned)vm->screen.cells[r * vm->screen.cols + c].fg);
                    }
                    fputc(']', stdout);
                }
                fputs("],\"bg\":[", stdout);
                for (r = 0; r < vm->screen.rows; r++) {
                    if (r > 0) fputc(',', stdout);
                    fputc('[', stdout);
                    for (c = 0; c < vm->screen.cols; c++) {
                        if (c > 0) fputc(',', stdout);
                        fprintf(stdout, "%u", (unsigned)vm->screen.cells[r * vm->screen.cols + c].bg);
                    }
                    fputc(']', stdout);
                }
                fputs("],\"attr\":[", stdout);
                for (r = 0; r < vm->screen.rows; r++) {
                    if (r > 0) fputc(',', stdout);
                    fputc('[', stdout);
                    for (c = 0; c < vm->screen.cols; c++) {
                        if (c > 0) fputc(',', stdout);
                        fprintf(stdout, "%u", (unsigned)vm->screen.cells[r * vm->screen.cols + c].attr);
                    }
                    fputc(']', stdout);
                }
                fputc(']', stdout);
            }
            fputs("}\n", stdout);
            fflush(stdout);
        } else if (strcmp(cmd, "reset") == 0) {
            const char *new_com = json_as_str(json_obj_get(req, "com_path"), NULL);
            const char *new_tail = json_as_str(json_obj_get(req, "tail"), NULL);
            int64_t new_tpa = 0;
            bool clear_out = true, clear_in = true;
            char load_err[256];
            char target_com[1024];

            json_as_bool(json_obj_get(req, "clear_output"), &clear_out);
            json_as_bool(json_obj_get(req, "clear_input"), &clear_in);
            if (json_as_int(json_obj_get(req, "tpa_top"), &new_tpa)) {
                if (new_tpa < 0x0200 || new_tpa > 0xFE00) {
                    emit_err(req, "invalid tpa_top (must be 0x0200..0xFE00)");
                    json_free(req);
                    continue;
                }
                vm->tpa_top = (uint16_t)new_tpa;
            }
            if (new_tail) {
                snprintf(vm->cli_tail, sizeof(vm->cli_tail), "%s", new_tail);
            }
            if (new_com) {
                snprintf(target_com, sizeof(target_com), "%s", new_com);
            } else {
                snprintf(target_com, sizeof(target_com), "%s", vm->com_path);
            }
            if (!target_com[0]) {
                emit_err(req, "no com_path loaded or specified");
                json_free(req);
                continue;
            }
            vm->total_steps = 0;
            vm->cur_drive = 0;
            vm->user_code = 0;
            vm->login_vec = 0;
            vm->ro_vec = 0;
            free(vm->search_matches);
            vm->search_matches = NULL;
            vm->search_count = 0;
            vm->search_idx = 0;
            if (clear_out) vm->out_len = 0;
            if (clear_in) cpm_clear_input(vm);
            ansi_reset(&vm->screen);
            if (!cpm_load_com(vm, target_com, load_err, sizeof(load_err))) {
                emit_err(req, load_err);
                json_free(req);
                continue;
            }
            fputc('{', stdout);
            emit_id_prefix(stdout, req);
            fputs("\"ok\":true,", stdout);
            emit_regs_fields(stdout, vm);
            fputs("}\n", stdout);
            fflush(stdout);
        } else if (strcmp(cmd, "quit") == 0) {
            fputc('{', stdout);
            emit_id_prefix(stdout, req);
            fputs("\"ok\":true,\"bye\":true}\n", stdout);
            fflush(stdout);
            json_free(req);
            break;
        } else {
            emit_err(req, "unknown cmd");
        }

    next_line:
        json_free(req);
    }

    free(line);
    return 0;
}

static void print_usage(const char *prog) {
    fprintf(stderr,
            "usage: %s [options] [program.com [args...]]\n"
            "  --control               JSON-lines control mode on stdin/stdout (zero sockets)\n"
            "  --tpa-top <addr>        BDOS/TPA ceiling stored at $0006-$0007 (default 0xE000)\n"
            "  --workdir <dir>         Base working directory for CP/M drives (default .)\n"
            "  --drive <A..P>=<dir>    Map specific CP/M drive letter to host directory\n"
            "  --layout auto|flat|runcpm  Drive directory layout (default auto)\n"
            "  --strict-drives         Only allow explicitly mapped or existing drive dirs\n"
            "  --strict-tpa            Fail if .COM image size exceeds tpa_top - 0x0100\n"
            "  --no-strict-bdos        Disable BDOS register clobber, stack poison, & strict FCB checks\n"
            "  --tail <str>            Explicit CP/M command tail for $0080\n"
            "  --raw-tail              Keep CLI tail verbatim without leading space/uppercase\n"
            "  --input <str>           Initial console input bytes\n"
            "  --input-hex <hex>       Initial console input bytes in hex\n"
            "  --max-steps <N>         Batch instruction limit (0 = unlimited, default 100000000)\n"
            "  --cols <N>              ANSI screen width (default 80)\n"
            "  --rows <N>              ANSI screen height (default 24)\n"
            "  --mask7                 Mask console output bytes to 7-bit (& 0x7F)\n"
            "  --quiet                 Suppress echoing CP/M console output to stdout in batch mode\n"
            "  --dump-mem <addr>:<len>[:<file>]  Dump RAM range after batch execution\n"
            "  --screen-dump           Print ANSI screen lines to stderr after batch execution\n"
            "  --summary-json          Print batch execution summary JSON\n",
            prog);
}

int main(int argc, char **argv) {
    CpmVm *vm = (CpmVm *)calloc(1, sizeof(CpmVm));
    bool control_mode = false;
    bool quiet = false;
    bool summary_json = false;
    bool screen_dump = false;
    bool has_dump_mem = false;
    uint16_t dump_addr = 0;
    uint32_t dump_len = 0;
    char dump_file[1024];
    bool explicit_tail = false;
    bool explicit_max_steps = false;
    uint64_t max_steps = 100000000ULL;
    int cols = 80, rows = 24;
    const char *com_path = NULL;
    char load_err[256];
    int i;
    int rc = 0;

    if (!vm) {
        fprintf(stderr, "ERROR: out of memory allocating CpmVm\n");
        return 1;
    }
    cpm_vm_init(vm);
    dump_file[0] = '\0';

    for (i = 1; i < argc; i++) {
        const char *arg = argv[i];
        if (strcmp(arg, "--help") == 0 || strcmp(arg, "-h") == 0) {
            print_usage(argv[0]);
            cpm_vm_free(vm);
            free(vm);
            return 0;
        } else if (strcmp(arg, "--control") == 0) {
            control_mode = true;
        } else if (strcmp(arg, "--tpa-top") == 0 && i + 1 < argc) {
            if (!parse_u16(argv[++i], &vm->tpa_top) || vm->tpa_top < 0x0200 || vm->tpa_top > 0xFE00) {
                fprintf(stderr, "ERROR: invalid --tpa-top '%s' (must be 0x0200..0xFE00)\n", argv[i]);
                cpm_vm_free(vm);
                free(vm);
                return 2;
            }
        } else if (strcmp(arg, "--workdir") == 0 && i + 1 < argc) {
            snprintf(vm->workdir, sizeof(vm->workdir), "%s", argv[++i]);
        } else if (strcmp(arg, "--drive") == 0 && i + 1 < argc) {
            const char *spec = argv[++i];
            char d = (char)toupper((unsigned char)spec[0]);
            if (d < 'A' || d > 'P' || spec[1] != '=' || spec[2] == '\0') {
                fprintf(stderr, "ERROR: --drive requires X=/path (A..P), got '%s'\n", spec);
                cpm_vm_free(vm);
                free(vm);
                return 2;
            }
            vm->drive_explicit[d - 'A'] = true;
            snprintf(vm->drive_paths[d - 'A'], sizeof(vm->drive_paths[0]), "%s", spec + 2);
        } else if (strcmp(arg, "--layout") == 0 && i + 1 < argc) {
            const char *m = argv[++i];
            if (strcmp(m, "auto") == 0) vm->layout = CPM_LAYOUT_AUTO;
            else if (strcmp(m, "flat") == 0) vm->layout = CPM_LAYOUT_FLAT;
            else if (strcmp(m, "runcpm") == 0) vm->layout = CPM_LAYOUT_RUNCPM;
            else {
                fprintf(stderr, "ERROR: unknown --layout '%s'\n", m);
                cpm_vm_free(vm);
                free(vm);
                return 2;
            }
        } else if (strcmp(arg, "--strict-drives") == 0) {
            vm->strict_drives = true;
        } else if (strcmp(arg, "--strict-tpa") == 0) {
            vm->strict_tpa = true;
        } else if (strcmp(arg, "--no-strict-bdos") == 0) {
            vm->strict_bdos = false;
        } else if (strcmp(arg, "--tail") == 0 && i + 1 < argc) {
            snprintf(vm->cli_tail, sizeof(vm->cli_tail), "%s", argv[++i]);
            explicit_tail = true;
        } else if (strcmp(arg, "--raw-tail") == 0) {
            vm->raw_tail = true;
        } else if (strcmp(arg, "--input") == 0 && i + 1 < argc) {
            const char *s = argv[++i];
            cpm_push_input(vm, (const uint8_t *)s, strlen(s));
        } else if (strcmp(arg, "--input-hex") == 0 && i + 1 < argc) {
            const char *hs = argv[++i];
            size_t hlen = strlen(hs);
            uint8_t *tmp = (uint8_t *)malloc(hlen / 2 + 1);
            size_t dec = 0;
            if (!tmp || !hex_decode(hs, tmp, hlen / 2 + 1, &dec)) {
                free(tmp);
                fprintf(stderr, "ERROR: invalid --input-hex\n");
                cpm_vm_free(vm);
                free(vm);
                return 2;
            }
            cpm_push_input(vm, tmp, dec);
            free(tmp);
        } else if (strcmp(arg, "--max-steps") == 0 && i + 1 < argc) {
            if (!parse_u64(argv[++i], &max_steps)) {
                fprintf(stderr, "ERROR: invalid --max-steps '%s'\n", argv[i]);
                cpm_vm_free(vm);
                free(vm);
                return 2;
            }
            explicit_max_steps = true;
        } else if (strcmp(arg, "--cols") == 0 && i + 1 < argc) {
            cols = atoi(argv[++i]);
        } else if (strcmp(arg, "--rows") == 0 && i + 1 < argc) {
            rows = atoi(argv[++i]);
        } else if (strcmp(arg, "--mask7") == 0) {
            vm->mask_7bit = true;
        } else if (strcmp(arg, "--quiet") == 0) {
            quiet = true;
        } else if (strcmp(arg, "--summary-json") == 0) {
            summary_json = true;
        } else if (strcmp(arg, "--screen-dump") == 0) {
            screen_dump = true;
        } else if (strcmp(arg, "--dump-mem") == 0 && i + 1 < argc) {
            const char *spec = argv[++i];
            const char *c1 = strchr(spec, ':');
            const char *c2 = c1 ? strchr(c1 + 1, ':') : NULL;
            char a_buf[32], l_buf[32];
            uint64_t lval = 0;
            if (!c1 || (size_t)(c1 - spec) >= sizeof(a_buf)) {
                fprintf(stderr, "ERROR: --dump-mem requires addr:len[:file]\n");
                cpm_vm_free(vm);
                free(vm);
                return 2;
            }
            memcpy(a_buf, spec, (size_t)(c1 - spec));
            a_buf[c1 - spec] = '\0';
            if (c2) {
                if ((size_t)(c2 - (c1 + 1)) >= sizeof(l_buf)) {
                    fprintf(stderr, "ERROR: invalid length in --dump-mem\n");
                    cpm_vm_free(vm);
                    free(vm);
                    return 2;
                }
                memcpy(l_buf, c1 + 1, (size_t)(c2 - (c1 + 1)));
                l_buf[c2 - (c1 + 1)] = '\0';
                snprintf(dump_file, sizeof(dump_file), "%s", c2 + 1);
            } else {
                snprintf(l_buf, sizeof(l_buf), "%s", c1 + 1);
            }
            if (!parse_u16(a_buf, &dump_addr) || !parse_u64(l_buf, &lval) ||
                (uint64_t)dump_addr + lval > 65536ULL) {
                fprintf(stderr, "ERROR: invalid addr/len in --dump-mem\n");
                cpm_vm_free(vm);
                free(vm);
                return 2;
            }
            dump_len = (uint32_t)lval;
            has_dump_mem = true;
        } else if (arg[0] == '-' && arg[1] != '\0') {
            fprintf(stderr, "ERROR: unknown option '%s'\n", arg);
            print_usage(argv[0]);
            cpm_vm_free(vm);
            free(vm);
            return 2;
        } else {
            com_path = arg;
            i++;
            break;
        }
    }

    ansi_init(&vm->screen, rows, cols);

    if (!explicit_tail && com_path && i < argc) {
        size_t pos = 0;
        int j;
        for (j = i; j < argc; j++) {
            const char *part = argv[j];
            size_t plen = strlen(part);
            if (pos > 0 && pos + 1 < sizeof(vm->cli_tail)) {
                vm->cli_tail[pos++] = ' ';
            }
            if (pos + plen >= sizeof(vm->cli_tail)) {
                plen = sizeof(vm->cli_tail) - pos - 1;
            }
            if (plen > 0) {
                memcpy(vm->cli_tail + pos, part, plen);
                pos += plen;
            }
        }
        vm->cli_tail[pos] = '\0';
    }

    if (com_path) {
        if (!cpm_load_com(vm, com_path, load_err, sizeof(load_err))) {
            fprintf(stderr, "ERROR: %s\n", load_err);
            cpm_vm_free(vm);
            free(vm);
            return 1;
        }
    } else if (!control_mode) {
        print_usage(argv[0]);
        cpm_vm_free(vm);
        free(vm);
        return 2;
    }

    if (control_mode) {
        rc = run_control_loop(vm);
        cpm_vm_free(vm);
        free(vm);
        return rc;
    }

    vm->echo_stdout = !quiet;
    vm->stop_on_wait_input = false;
    vm->stop_on_idle = false;
    if (isatty(STDIN_FILENO)) {
        struct termios raw;
        vm->interactive_tty = true;
        vm->stop_flag = &g_stop_flag;
        if (!explicit_max_steps) {
            max_steps = 0;
        }
        if (tcgetattr(STDIN_FILENO, &g_orig_termios) == 0) {
            raw = g_orig_termios;
            raw.c_iflag &= ~(tcflag_t)(ICRNL | IXON);
            raw.c_lflag &= ~(tcflag_t)(ICANON | ECHO | IEXTEN);
            raw.c_cc[VMIN] = 1;
            raw.c_cc[VTIME] = 0;
            if (tcsetattr(STDIN_FILENO, TCSANOW, &raw) == 0) {
                struct sigaction sa;
                g_tty_raw = true;
                atexit(restore_tty);
                memset(&sa, 0, sizeof(sa));
                sa.sa_handler = on_signal;
                sigemptyset(&sa.sa_mask);
                sigaction(SIGINT, &sa, NULL);
                sigaction(SIGTERM, &sa, NULL);
            }
        }
    }
    z80_run(vm, max_steps);
    restore_tty();

    if (vm->status == CPM_STEP_LIMIT) {
        vm->exit_code = 2;
        snprintf(vm->exit_reason, sizeof(vm->exit_reason), "step_limit");
    }

    if (has_dump_mem) {
        if (dump_file[0]) {
            FILE *df = fopen(dump_file, "wb");
            if (!df) {
                fprintf(stderr, "ERROR: cannot write dump file '%s': %s\n", dump_file, strerror(errno));
                cpm_vm_free(vm);
                free(vm);
                return 1;
            }
            fwrite(&vm->ram[dump_addr], 1, dump_len, df);
            fclose(df);
        } else {
            FILE *out = quiet ? stdout : stderr;
            uint32_t k;
            fprintf(out, "MEM $%04X (%u bytes):", (unsigned)dump_addr, (unsigned)dump_len);
            for (k = 0; k < dump_len; k++) {
                fprintf(out, "%s%02X", (k % 16 == 0) ? "\n  " : " ", (unsigned)vm->ram[dump_addr + k]);
            }
            fputc('\n', out);
        }
    }

    if (screen_dump) {
        int r, c;
        for (r = 0; r < vm->screen.rows; r++) {
            fprintf(stderr, "%02d|", r);
            for (c = 0; c < vm->screen.cols; c++) {
                uint8_t ch = vm->screen.cells[r * vm->screen.cols + c].ch;
                fputc((ch >= 0x20 && ch < 0x7F) ? (char)ch : ' ', stderr);
            }
            fputs("|\n", stderr);
        }
    }

    if (summary_json) {
        FILE *sf = quiet ? stdout : stderr;
        fputc('{', sf);
        emit_regs_fields(sf, vm);
        fprintf(sf, ",\"console_out_len\":%zu}\n", vm->out_len);
    }

    rc = vm->exit_code;
    cpm_vm_free(vm);
    free(vm);
    return rc;
}

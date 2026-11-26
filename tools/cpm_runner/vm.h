#ifndef CPM_RUNNER_VM_H
#define CPM_RUNNER_VM_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define ANSI_MAX_ROWS 64
#define ANSI_MAX_COLS 160

#define ANSI_ATTR_BOLD      0x01
#define ANSI_ATTR_UNDERLINE 0x04
#define ANSI_ATTR_REVERSE   0x08

#define CPM_MAX_OPEN_FCBS   256

typedef struct {
    uint8_t ch;
    uint8_t fg;
    uint8_t bg;
    uint8_t attr;
} AnsiCell;

typedef enum {
    ANSI_STATE_NORMAL = 0,
    ANSI_STATE_ESC,
    ANSI_STATE_CSI,
    ANSI_STATE_CSI_PRIV,
    ANSI_STATE_ADM_ROW,
    ANSI_STATE_ADM_COL
} AnsiParseState;

typedef struct {
    int rows;
    int cols;
    int cur_row;
    int cur_col;
    int saved_row;
    int saved_col;
    uint8_t cur_fg;
    uint8_t cur_bg;
    uint8_t cur_attr;
    uint8_t saved_fg;
    uint8_t saved_bg;
    uint8_t saved_attr;
    bool cursor_visible;
    bool wrap_pending;
    AnsiParseState state;
    int params[16];
    int nparams;
    int cur_param;
    bool has_param;
    AnsiCell cells[ANSI_MAX_ROWS * ANSI_MAX_COLS];
} AnsiScreen;

typedef enum {
    CPM_RUNNING = 0,
    CPM_EXITED = 1,
    CPM_HALTED = 2,
    CPM_WAIT_INPUT = 3,
    CPM_IDLE = 4,
    CPM_BREAKPOINT = 5,
    CPM_STEP_LIMIT = 6,
    CPM_FAULT = 7
} CpmStatus;

typedef enum {
    CPM_LAYOUT_AUTO = 0,
    CPM_LAYOUT_FLAT = 1,
    CPM_LAYOUT_RUNCPM = 2
} CpmLayoutMode;

typedef struct {
    char host_name[256];
    uint8_t cpm_name[11];
    uint32_t size_bytes;
} CpmDirMatch;

typedef struct {
    bool active;
    uint16_t fcb_addr;
    uint8_t drive;
    uint8_t name11[11];
} CpmOpenFcb;

typedef struct {
    uint8_t ram[65536];

    uint32_t af;
    uint32_t bc;
    uint32_t de;
    uint32_t hl;
    uint32_t ix;
    uint32_t iy;
    uint32_t pc;
    uint32_t sp;
    uint32_t af1;
    uint32_t bc1;
    uint32_t de1;
    uint32_t hl1;
    uint32_t iff;
    uint32_t ir;

    CpmStatus status;
    int exit_code;
    char exit_reason[64];
    uint64_t total_steps;
    uint32_t idle_polls;
    uint32_t idle_poll_threshold;
    bool stop_on_idle;
    bool stop_on_wait_input;

    uint16_t breakpoints[64];
    size_t num_breakpoints;

    uint16_t tpa_top;
    uint16_t bdos_entry;
    uint16_t bios_base;
    uint16_t dma_addr;
    uint8_t cur_drive;
    uint8_t user_code;
    uint16_t login_vec;
    uint16_t ro_vec;

    bool strict_bdos;
    CpmOpenFcb open_fcbs[CPM_MAX_OPEN_FCBS];

    bool readstr_active;
    uint16_t readstr_buf;
    uint8_t readstr_max;
    uint8_t readstr_cnt;

    CpmLayoutMode layout;
    char workdir[1024];
    char drive_paths[16][1024];
    bool drive_explicit[16];
    bool strict_drives;

    CpmDirMatch *search_matches;
    size_t search_count;
    size_t search_idx;
    uint8_t search_drive;

    uint8_t *in_buf;
    size_t in_head;
    size_t in_tail;
    size_t in_cap;
    bool stdin_eof;

    uint8_t *out_buf;
    size_t out_len;
    size_t out_cap;

    bool echo_stdout;
    bool interactive_tty;
    volatile int *stop_flag;
    bool mask_7bit;
    bool strict_tpa;

    AnsiScreen screen;

    char com_path[1024];
    char cli_tail[128];
    bool raw_tail;
} CpmVm;

const char *cpm_status_name(CpmStatus st);

#endif

#include "ansi.h"

#include <string.h>

static void ansi_clear_cell(AnsiCell *c, uint8_t fg, uint8_t bg, uint8_t attr) {
    c->ch = ' ';
    c->fg = fg;
    c->bg = bg;
    c->attr = attr;
}

static void ansi_clear_range(AnsiScreen *s, int r0, int c0, int r1, int c1) {
    int r, c;
    for (r = r0; r <= r1; r++) {
        int start_c = (r == r0) ? c0 : 0;
        int end_c = (r == r1) ? c1 : (s->cols - 1);
        for (c = start_c; c <= end_c; c++) {
            ansi_clear_cell(&s->cells[r * s->cols + c], s->cur_fg, s->cur_bg, 0);
        }
    }
}

static void ansi_scroll_up(AnsiScreen *s) {
    if (s->rows <= 1) {
        ansi_clear_range(s, 0, 0, s->rows - 1, s->cols - 1);
        return;
    }
    memmove(&s->cells[0], &s->cells[s->cols],
            (size_t)(s->rows - 1) * (size_t)s->cols * sizeof(AnsiCell));
    ansi_clear_range(s, s->rows - 1, 0, s->rows - 1, s->cols - 1);
}

void ansi_init(AnsiScreen *s, int rows, int cols) {
    if (rows < 1) rows = 24;
    if (rows > ANSI_MAX_ROWS) rows = ANSI_MAX_ROWS;
    if (cols < 1) cols = 80;
    if (cols > ANSI_MAX_COLS) cols = ANSI_MAX_COLS;
    s->rows = rows;
    s->cols = cols;
    ansi_reset(s);
}

void ansi_reset(AnsiScreen *s) {
    int r = s->rows;
    int c = s->cols;
    memset(s, 0, sizeof(*s));
    s->rows = r > 0 ? r : 24;
    s->cols = c > 0 ? c : 80;
    s->cur_fg = 7;
    s->cur_bg = 0;
    s->saved_fg = 7;
    s->saved_bg = 0;
    s->cursor_visible = true;
    ansi_clear_range(s, 0, 0, s->rows - 1, s->cols - 1);
}

static int ansi_param(const AnsiScreen *s, int idx, int def_val) {
    if (idx >= s->nparams || s->params[idx] <= 0) {
        return def_val;
    }
    return s->params[idx];
}

static int ansi_param_raw(const AnsiScreen *s, int idx, int def_val) {
    if (idx >= s->nparams) {
        return def_val;
    }
    return s->params[idx];
}

static void ansi_handle_sgr(AnsiScreen *s) {
    int i;
    if (s->nparams == 0) {
        s->cur_fg = 7;
        s->cur_bg = 0;
        s->cur_attr = 0;
        return;
    }
    for (i = 0; i < s->nparams; i++) {
        int p = s->params[i];
        if (p == 0) {
            s->cur_fg = 7;
            s->cur_bg = 0;
            s->cur_attr = 0;
        } else if (p == 1) {
            s->cur_attr |= ANSI_ATTR_BOLD;
        } else if (p == 4) {
            s->cur_attr |= ANSI_ATTR_UNDERLINE;
        } else if (p == 7) {
            s->cur_attr |= ANSI_ATTR_REVERSE;
        } else if (p == 22) {
            s->cur_attr &= (uint8_t)~ANSI_ATTR_BOLD;
        } else if (p == 24) {
            s->cur_attr &= (uint8_t)~ANSI_ATTR_UNDERLINE;
        } else if (p == 27) {
            s->cur_attr &= (uint8_t)~ANSI_ATTR_REVERSE;
        } else if (p >= 30 && p <= 37) {
            s->cur_fg = (uint8_t)(p - 30);
        } else if (p == 39) {
            s->cur_fg = 7;
        } else if (p >= 40 && p <= 47) {
            s->cur_bg = (uint8_t)(p - 40);
        } else if (p == 49) {
            s->cur_bg = 0;
        } else if (p >= 90 && p <= 97) {
            s->cur_fg = (uint8_t)((p - 90) + 8);
        } else if (p >= 100 && p <= 107) {
            s->cur_bg = (uint8_t)((p - 100) + 8);
        }
    }
}

static void ansi_clamp_cursor(AnsiScreen *s) {
    if (s->cur_row < 0) s->cur_row = 0;
    if (s->cur_row >= s->rows) s->cur_row = s->rows - 1;
    if (s->cur_col < 0) s->cur_col = 0;
    if (s->cur_col >= s->cols) s->cur_col = s->cols - 1;
}

static void ansi_dispatch_csi(AnsiScreen *s, uint8_t final_ch) {
    if (s->has_param && s->nparams < 16) {
        s->params[s->nparams++] = s->cur_param;
    }

    if (s->state == ANSI_STATE_CSI_PRIV) {
        int p0 = ansi_param_raw(s, 0, 0);
        if (p0 == 25) {
            if (final_ch == 'h') s->cursor_visible = true;
            else if (final_ch == 'l') s->cursor_visible = false;
        }
        s->state = ANSI_STATE_NORMAL;
        return;
    }

    switch (final_ch) {
    case 'A':
        s->cur_row -= ansi_param(s, 0, 1);
        s->wrap_pending = false;
        ansi_clamp_cursor(s);
        break;
    case 'B':
        s->cur_row += ansi_param(s, 0, 1);
        s->wrap_pending = false;
        ansi_clamp_cursor(s);
        break;
    case 'C':
        s->cur_col += ansi_param(s, 0, 1);
        s->wrap_pending = false;
        ansi_clamp_cursor(s);
        break;
    case 'D':
        s->cur_col -= ansi_param(s, 0, 1);
        s->wrap_pending = false;
        ansi_clamp_cursor(s);
        break;
    case 'G':
        s->cur_col = ansi_param(s, 0, 1) - 1;
        s->wrap_pending = false;
        ansi_clamp_cursor(s);
        break;
    case 'H':
    case 'f':
        s->cur_row = ansi_param(s, 0, 1) - 1;
        s->cur_col = ansi_param(s, 1, 1) - 1;
        s->wrap_pending = false;
        ansi_clamp_cursor(s);
        break;
    case 'J': {
        int mode = ansi_param_raw(s, 0, 0);
        s->wrap_pending = false;
        if (mode == 0) {
            ansi_clear_range(s, s->cur_row, s->cur_col, s->rows - 1, s->cols - 1);
        } else if (mode == 1) {
            ansi_clear_range(s, 0, 0, s->cur_row, s->cur_col);
        } else if (mode == 2 || mode == 3) {
            ansi_clear_range(s, 0, 0, s->rows - 1, s->cols - 1);
        }
        break;
    }
    case 'K': {
        int mode = ansi_param_raw(s, 0, 0);
        s->wrap_pending = false;
        if (mode == 0) {
            ansi_clear_range(s, s->cur_row, s->cur_col, s->cur_row, s->cols - 1);
        } else if (mode == 1) {
            ansi_clear_range(s, s->cur_row, 0, s->cur_row, s->cur_col);
        } else if (mode == 2) {
            ansi_clear_range(s, s->cur_row, 0, s->cur_row, s->cols - 1);
        }
        break;
    }
    case 'm':
        ansi_handle_sgr(s);
        break;
    case 's':
        s->saved_row = s->cur_row;
        s->saved_col = s->cur_col;
        s->saved_fg = s->cur_fg;
        s->saved_bg = s->cur_bg;
        s->saved_attr = s->cur_attr;
        break;
    case 'u':
        s->cur_row = s->saved_row;
        s->cur_col = s->saved_col;
        s->cur_fg = s->saved_fg;
        s->cur_bg = s->saved_bg;
        s->cur_attr = s->saved_attr;
        s->wrap_pending = false;
        ansi_clamp_cursor(s);
        break;
    default:
        break;
    }
    s->state = ANSI_STATE_NORMAL;
}

void ansi_putc(AnsiScreen *s, uint8_t ch) {
    if (s->state == ANSI_STATE_ESC) {
        if (ch == '[') {
            s->state = ANSI_STATE_CSI;
            s->nparams = 0;
            s->cur_param = 0;
            s->has_param = false;
            return;
        } else if (ch == '=') {
            s->state = ANSI_STATE_ADM_ROW;
            return;
        } else if (ch == '7') {
            s->saved_row = s->cur_row;
            s->saved_col = s->cur_col;
            s->saved_fg = s->cur_fg;
            s->saved_bg = s->cur_bg;
            s->saved_attr = s->cur_attr;
            s->state = ANSI_STATE_NORMAL;
            return;
        } else if (ch == '8') {
            s->cur_row = s->saved_row;
            s->cur_col = s->saved_col;
            s->cur_fg = s->saved_fg;
            s->cur_bg = s->saved_bg;
            s->cur_attr = s->saved_attr;
            s->wrap_pending = false;
            ansi_clamp_cursor(s);
            s->state = ANSI_STATE_NORMAL;
            return;
        } else if (ch == 'c') {
            ansi_reset(s);
            return;
        }
        s->state = ANSI_STATE_NORMAL;
        return;
    }

    if (s->state == ANSI_STATE_ADM_ROW) {
        s->cur_row = (int)ch - 0x20;
        s->state = ANSI_STATE_ADM_COL;
        return;
    }

    if (s->state == ANSI_STATE_ADM_COL) {
        s->cur_col = (int)ch - 0x20;
        s->wrap_pending = false;
        ansi_clamp_cursor(s);
        s->state = ANSI_STATE_NORMAL;
        return;
    }

    if (s->state == ANSI_STATE_CSI || s->state == ANSI_STATE_CSI_PRIV) {
        if (ch == '?' && s->nparams == 0 && !s->has_param) {
            s->state = ANSI_STATE_CSI_PRIV;
            return;
        }
        if (ch >= '0' && ch <= '9') {
            s->cur_param = s->cur_param * 10 + (ch - '0');
            if (s->cur_param > 9999) s->cur_param = 9999;
            s->has_param = true;
            return;
        }
        if (ch == ';') {
            if (s->nparams < 16) {
                s->params[s->nparams++] = s->has_param ? s->cur_param : 0;
            }
            s->cur_param = 0;
            s->has_param = false;
            return;
        }
        if (ch >= 0x40 && ch <= 0x7E) {
            ansi_dispatch_csi(s, ch);
            return;
        }
        if (ch == 0x1B) {
            s->state = ANSI_STATE_ESC;
            return;
        }
        return;
    }

    switch (ch) {
    case 0x1B:
        s->state = ANSI_STATE_ESC;
        return;
    case '\r':
        s->cur_col = 0;
        s->wrap_pending = false;
        return;
    case '\n':
        s->wrap_pending = false;
        s->cur_row++;
        if (s->cur_row >= s->rows) {
            ansi_scroll_up(s);
            s->cur_row = s->rows - 1;
        }
        return;
    case '\b':
        s->wrap_pending = false;
        if (s->cur_col > 0) {
            s->cur_col--;
        }
        return;
    case '\t': {
        int next_col = (s->cur_col + 8) & ~7;
        s->wrap_pending = false;
        if (next_col >= s->cols) next_col = s->cols - 1;
        s->cur_col = next_col;
        return;
    }
    case 0x07:
        return;
    case 0x1A:
        s->wrap_pending = false;
        s->cur_row = 0;
        s->cur_col = 0;
        ansi_clear_range(s, 0, 0, s->rows - 1, s->cols - 1);
        return;
    case 0x1E:
        s->wrap_pending = false;
        s->cur_row = 0;
        s->cur_col = 0;
        return;
    default:
        if (ch < 0x20 || ch == 0x7F) {
            return;
        }
        if (s->wrap_pending) {
            s->wrap_pending = false;
            s->cur_col = 0;
            s->cur_row++;
            if (s->cur_row >= s->rows) {
                ansi_scroll_up(s);
                s->cur_row = s->rows - 1;
            }
        }
        {
            AnsiCell *cell = &s->cells[s->cur_row * s->cols + s->cur_col];
            cell->ch = ch;
            cell->fg = s->cur_fg;
            cell->bg = s->cur_bg;
            cell->attr = s->cur_attr;
        }
        if (s->cur_col + 1 >= s->cols) {
            s->wrap_pending = true;
        } else {
            s->cur_col++;
        }
        return;
    }
}

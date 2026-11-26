#include <stdio.h>
#include "json.h"

#include <ctype.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    const char *p;
    char *err;
    size_t err_cap;
} JParser;

static void skip_ws(JParser *jp) {
    while (*jp->p == ' ' || *jp->p == '\t' || *jp->p == '\r' || *jp->p == '\n') {
        jp->p++;
    }
}

static void set_err(JParser *jp, const char *msg) {
    if (jp->err && jp->err_cap > 0 && jp->err[0] == '\0') {
        snprintf(jp->err, jp->err_cap, "%s", msg);
    }
}

static JVal *parse_value(JParser *jp);

static char *parse_string_raw(JParser *jp, size_t *out_len) {
    size_t cap = 64;
    size_t len = 0;
    char *buf = (char *)malloc(cap);
    if (!buf) {
        set_err(jp, "out of memory");
        return NULL;
    }
    if (*jp->p != '"') {
        free(buf);
        set_err(jp, "expected '\"'");
        return NULL;
    }
    jp->p++;
    while (*jp->p && *jp->p != '"') {
        unsigned char c = (unsigned char)*jp->p++;
        if (c == '\\') {
            unsigned char esc = (unsigned char)*jp->p++;
            if (!esc) {
                free(buf);
                set_err(jp, "unterminated escape");
                return NULL;
            }
            switch (esc) {
            case '"':  c = '"'; break;
            case '\\': c = '\\'; break;
            case '/':  c = '/'; break;
            case 'b':  c = '\b'; break;
            case 'f':  c = '\f'; break;
            case 'n':  c = '\n'; break;
            case 'r':  c = '\r'; break;
            case 't':  c = '\t'; break;
            case 'u': {
                unsigned int code = 0;
                int k;
                for (k = 0; k < 4; k++) {
                    unsigned char h = (unsigned char)*jp->p++;
                    code <<= 4;
                    if (h >= '0' && h <= '9') code |= (unsigned int)(h - '0');
                    else if (h >= 'a' && h <= 'f') code |= (unsigned int)(h - 'a' + 10);
                    else if (h >= 'A' && h <= 'F') code |= (unsigned int)(h - 'A' + 10);
                    else {
                        free(buf);
                        set_err(jp, "invalid \\u escape");
                        return NULL;
                    }
                }
                c = (unsigned char)(code & 0xFF);
                break;
            }
            default:
                free(buf);
                set_err(jp, "unknown escape sequence");
                return NULL;
            }
        }
        if (len + 2 >= cap) {
            char *nb = (char *)realloc(buf, cap * 2);
            if (!nb) {
                free(buf);
                set_err(jp, "out of memory");
                return NULL;
            }
            buf = nb;
            cap *= 2;
        }
        buf[len++] = (char)c;
    }
    if (*jp->p != '"') {
        free(buf);
        set_err(jp, "unterminated string");
        return NULL;
    }
    jp->p++;
    buf[len] = '\0';
    if (out_len) *out_len = len;
    return buf;
}

static JVal *parse_array(JParser *jp) {
    JVal *v = (JVal *)calloc(1, sizeof(JVal));
    size_t cap = 8;
    if (!v) return NULL;
    v->type = JVAL_ARR;
    v->u.arr.items = (JVal **)malloc(cap * sizeof(JVal *));
    if (!v->u.arr.items) {
        free(v);
        return NULL;
    }
    jp->p++; /* '[' */
    skip_ws(jp);
    if (*jp->p == ']') {
        jp->p++;
        return v;
    }
    while (1) {
        JVal *item;
        skip_ws(jp);
        item = parse_value(jp);
        if (!item) {
            json_free(v);
            return NULL;
        }
        if (v->u.arr.len >= cap) {
            JVal **ni = (JVal **)realloc(v->u.arr.items, cap * 2 * sizeof(JVal *));
            if (!ni) {
                json_free(item);
                json_free(v);
                return NULL;
            }
            v->u.arr.items = ni;
            cap *= 2;
        }
        v->u.arr.items[v->u.arr.len++] = item;
        skip_ws(jp);
        if (*jp->p == ',') {
            jp->p++;
            continue;
        }
        if (*jp->p == ']') {
            jp->p++;
            return v;
        }
        set_err(jp, "expected ',' or ']'");
        json_free(v);
        return NULL;
    }
}

static JVal *parse_object(JParser *jp) {
    JVal *v = (JVal *)calloc(1, sizeof(JVal));
    size_t cap = 8;
    if (!v) return NULL;
    v->type = JVAL_OBJ;
    v->u.obj.members = (JMember *)malloc(cap * sizeof(JMember));
    if (!v->u.obj.members) {
        free(v);
        return NULL;
    }
    jp->p++; /* '{' */
    skip_ws(jp);
    if (*jp->p == '}') {
        jp->p++;
        return v;
    }
    while (1) {
        char *key;
        JVal *val;
        skip_ws(jp);
        key = parse_string_raw(jp, NULL);
        if (!key) {
            json_free(v);
            return NULL;
        }
        skip_ws(jp);
        if (*jp->p != ':') {
            free(key);
            set_err(jp, "expected ':'");
            json_free(v);
            return NULL;
        }
        jp->p++;
        skip_ws(jp);
        val = parse_value(jp);
        if (!val) {
            free(key);
            json_free(v);
            return NULL;
        }
        if (v->u.obj.len >= cap) {
            JMember *nm = (JMember *)realloc(v->u.obj.members, cap * 2 * sizeof(JMember));
            if (!nm) {
                free(key);
                json_free(val);
                json_free(v);
                return NULL;
            }
            v->u.obj.members = nm;
            cap *= 2;
        }
        v->u.obj.members[v->u.obj.len].key = key;
        v->u.obj.members[v->u.obj.len].val = val;
        v->u.obj.len++;
        skip_ws(jp);
        if (*jp->p == ',') {
            jp->p++;
            continue;
        }
        if (*jp->p == '}') {
            jp->p++;
            return v;
        }
        set_err(jp, "expected ',' or '}'");
        json_free(v);
        return NULL;
    }
}

static JVal *parse_value(JParser *jp) {
    skip_ws(jp);
    switch (*jp->p) {
    case '{':
        return parse_object(jp);
    case '[':
        return parse_array(jp);
    case '"': {
        size_t len = 0;
        char *s = parse_string_raw(jp, &len);
        JVal *v;
        if (!s) return NULL;
        v = (JVal *)calloc(1, sizeof(JVal));
        if (!v) {
            free(s);
            return NULL;
        }
        v->type = JVAL_STR;
        v->u.s.ptr = s;
        v->u.s.len = len;
        return v;
    }
    case 't':
        if (strncmp(jp->p, "true", 4) == 0) {
            JVal *v = (JVal *)calloc(1, sizeof(JVal));
            if (!v) return NULL;
            v->type = JVAL_BOOL;
            v->u.b = true;
            jp->p += 4;
            return v;
        }
        set_err(jp, "invalid token");
        return NULL;
    case 'f':
        if (strncmp(jp->p, "false", 5) == 0) {
            JVal *v = (JVal *)calloc(1, sizeof(JVal));
            if (!v) return NULL;
            v->type = JVAL_BOOL;
            v->u.b = false;
            jp->p += 5;
            return v;
        }
        set_err(jp, "invalid token");
        return NULL;
    case 'n':
        if (strncmp(jp->p, "null", 4) == 0) {
            JVal *v = (JVal *)calloc(1, sizeof(JVal));
            if (!v) return NULL;
            v->type = JVAL_NULL;
            jp->p += 4;
            return v;
        }
        set_err(jp, "invalid token");
        return NULL;
    default:
        if (*jp->p == '-' || (*jp->p >= '0' && *jp->p <= '9')) {
            char *endp = NULL;
            long long val = strtoll(jp->p, &endp, 10);
            JVal *v;
            if (endp == jp->p) {
                set_err(jp, "invalid number");
                return NULL;
            }
            v = (JVal *)calloc(1, sizeof(JVal));
            if (!v) return NULL;
            v->type = JVAL_INT;
            v->u.i = (int64_t)val;
            jp->p = endp;
            return v;
        }
        set_err(jp, "unexpected character");
        return NULL;
    }
}

JVal *json_parse(const char *src, char *err_buf, size_t err_cap) {
    JParser jp;
    JVal *v;
    if (err_buf && err_cap > 0) err_buf[0] = '\0';
    jp.p = src;
    jp.err = err_buf;
    jp.err_cap = err_cap;
    v = parse_value(&jp);
    if (!v) return NULL;
    skip_ws(&jp);
    if (*jp.p != '\0') {
        set_err(&jp, "trailing characters after JSON value");
        json_free(v);
        return NULL;
    }
    return v;
}

void json_free(JVal *v) {
    size_t i;
    if (!v) return;
    switch (v->type) {
    case JVAL_STR:
        free(v->u.s.ptr);
        break;
    case JVAL_ARR:
        for (i = 0; i < v->u.arr.len; i++) json_free(v->u.arr.items[i]);
        free(v->u.arr.items);
        break;
    case JVAL_OBJ:
        for (i = 0; i < v->u.obj.len; i++) {
            free(v->u.obj.members[i].key);
            json_free(v->u.obj.members[i].val);
        }
        free(v->u.obj.members);
        break;
    default:
        break;
    }
    free(v);
}

const JVal *json_obj_get(const JVal *obj, const char *key) {
    size_t i;
    if (!obj || obj->type != JVAL_OBJ) return NULL;
    for (i = 0; i < obj->u.obj.len; i++) {
        if (strcmp(obj->u.obj.members[i].key, key) == 0) {
            return obj->u.obj.members[i].val;
        }
    }
    return NULL;
}

bool json_as_int(const JVal *v, int64_t *out) {
    if (!v) return false;
    if (v->type == JVAL_INT) {
        *out = v->u.i;
        return true;
    }
    if (v->type == JVAL_STR && v->u.s.ptr) {
        char *endp = NULL;
        const char *s = v->u.s.ptr;
        int base = 10;
        long long val;
        if (s[0] == '$') {
            s++;
            base = 16;
        } else if (s[0] == '0' && (s[1] == 'x' || s[1] == 'X')) {
            base = 16;
        }
        val = strtoll(s, &endp, base);
        if (endp != s && *endp == '\0') {
            *out = (int64_t)val;
            return true;
        }
    }
    return false;
}

bool json_as_bool(const JVal *v, bool *out) {
    if (!v || v->type != JVAL_BOOL) return false;
    *out = v->u.b;
    return true;
}

const char *json_as_str(const JVal *v, size_t *out_len) {
    if (!v || v->type != JVAL_STR) return NULL;
    if (out_len) *out_len = v->u.s.len;
    return v->u.s.ptr;
}

void json_emit_str(FILE *fp, const char *s, size_t len) {
    size_t i;
    fputc('"', fp);
    for (i = 0; i < len; i++) {
        unsigned char c = (unsigned char)s[i];
        switch (c) {
        case '"':  fputs("\\\"", fp); break;
        case '\\': fputs("\\\\", fp); break;
        case '\b': fputs("\\b", fp); break;
        case '\f': fputs("\\f", fp); break;
        case '\n': fputs("\\n", fp); break;
        case '\r': fputs("\\r", fp); break;
        case '\t': fputs("\\t", fp); break;
        default:
            if (c < 0x20 || c >= 0x7F) {
                fprintf(fp, "\\u%04x", (unsigned int)c);
            } else {
                fputc(c, fp);
            }
            break;
        }
    }
    fputc('"', fp);
}

void json_emit_hex(FILE *fp, const uint8_t *buf, size_t len) {
    static const char hx[] = "0123456789abcdef";
    size_t i;
    fputc('"', fp);
    for (i = 0; i < len; i++) {
        fputc(hx[(buf[i] >> 4) & 0x0F], fp);
        fputc(hx[buf[i] & 0x0F], fp);
    }
    fputc('"', fp);
}

static int hex_nibble(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

bool hex_decode(const char *hex, uint8_t *out, size_t max_out, size_t *out_len) {
    size_t n = 0;
    while (*hex) {
        int hi, lo;
        while (*hex == ' ' || *hex == '\t' || *hex == '\r' || *hex == '\n') hex++;
        if (!*hex) break;
        hi = hex_nibble(*hex++);
        if (hi < 0 || !*hex) return false;
        lo = hex_nibble(*hex++);
        if (lo < 0) return false;
        if (n >= max_out) return false;
        out[n++] = (uint8_t)((hi << 4) | lo);
    }
    *out_len = n;
    return true;
}

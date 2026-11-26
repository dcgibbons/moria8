#ifndef CPM_RUNNER_JSON_H
#define CPM_RUNNER_JSON_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

typedef enum {
    JVAL_NULL = 0,
    JVAL_BOOL,
    JVAL_INT,
    JVAL_STR,
    JVAL_ARR,
    JVAL_OBJ
} JValType;

typedef struct JVal JVal;

typedef struct {
    char *key;
    JVal *val;
} JMember;

struct JVal {
    JValType type;
    union {
        bool b;
        int64_t i;
        struct {
            char *ptr;
            size_t len;
        } s;
        struct {
            JVal **items;
            size_t len;
        } arr;
        struct {
            JMember *members;
            size_t len;
        } obj;
    } u;
};

JVal *json_parse(const char *src, char *err_buf, size_t err_cap);
void json_free(JVal *v);

const JVal *json_obj_get(const JVal *obj, const char *key);
bool json_as_int(const JVal *v, int64_t *out);
bool json_as_bool(const JVal *v, bool *out);
const char *json_as_str(const JVal *v, size_t *out_len);

void json_emit_str(FILE *fp, const char *s, size_t len);
void json_emit_hex(FILE *fp, const uint8_t *buf, size_t len);
bool hex_decode(const char *hex, uint8_t *out, size_t max_out, size_t *out_len);

#endif

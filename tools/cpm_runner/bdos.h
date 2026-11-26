#ifndef CPM_RUNNER_BDOS_H
#define CPM_RUNNER_BDOS_H

#include "vm.h"

void cpm_vm_init(CpmVm *vm);
void cpm_vm_free(CpmVm *vm);
void cpm_setup_page_zero(CpmVm *vm);
bool cpm_load_com(CpmVm *vm, const char *path, char *err_buf, size_t err_cap);

void cpm_push_input(CpmVm *vm, const uint8_t *data, size_t len);
void cpm_clear_input(CpmVm *vm);
size_t cpm_input_len(const CpmVm *vm);

/* Returns true if BDOS call finished and Z80 should RET; false if exited or suspended waiting for input */
bool bdos_call(CpmVm *vm);
/* Returns true if BIOS call finished and Z80 should RET; false if exited or suspended */
bool bios_call(CpmVm *vm, uint8_t func_index);

#endif

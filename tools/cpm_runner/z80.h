#ifndef CPM_RUNNER_Z80_H
#define CPM_RUNNER_Z80_H

#include "vm.h"

void z80_init_tables(void);
CpmStatus z80_run(CpmVm *vm, uint64_t max_steps);

#endif

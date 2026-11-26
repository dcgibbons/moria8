#ifndef CPM_RUNNER_ANSI_H
#define CPM_RUNNER_ANSI_H

#include "vm.h"

void ansi_init(AnsiScreen *s, int rows, int cols);
void ansi_reset(AnsiScreen *s);
void ansi_putc(AnsiScreen *s, uint8_t ch);

#endif

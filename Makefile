# Root Makefile — delegates to commodore/c64/
.PHONY: all build run rundisk debug test disk savedisk clean

all build run rundisk debug test disk savedisk clean:
	$(MAKE) -C commodore/c64 $@

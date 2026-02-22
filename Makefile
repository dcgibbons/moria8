# Root Makefile — delegates to commodore/c64/
.PHONY: all build run rundisk rundual debug test disk savedisk clean run128demo

all build run rundisk rundual debug test disk savedisk clean run128demo:
	$(MAKE) -C commodore/c64 $@

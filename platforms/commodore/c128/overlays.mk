# Additional C128 Phase 2/4 cold overlays wired into platforms/commodore/Makefile
C128_EXTRA_OVERLAYS = $(OUT128)/ovl.home $(OUT128)/ovl.storage
C128_EXTRA_OVERLAY_PAIRS = $(OUT128)/ovl.home:128.home $(OUT128)/ovl.storage:128.storage
C128_EXTRA_DISK_WRITES =

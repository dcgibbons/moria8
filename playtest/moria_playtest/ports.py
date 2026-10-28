"""What the driver needs to know about each port (§21.3).

The brain, goals and recorder are port-neutral: a port names its emulator,
disk and symbols, the source constants the ABI table checks, the KERNAL
addresses the driver writes keys to, and how a crash is told from banked RAM
code at a KERNAL address. Ports are added in §21.3's order.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Port:
    name: str                 # suite and command-line name; the C64's suites carry none
    emulator: str             # VICE binary
    out: str                  # build/<out>/ holds the program and its symbols
    program: str
    disk: str                 # build/<disk>, the shipping image
    disk_target: str          # the make target that writes it
    disk_files: dict[str, str]   # disk file -> the build output it is written from
    resource_args: tuple[str, ...]
    rom_env: tuple[tuple[str, str], ...]   # (environment variable, VICE option)
    required_roms: tuple[str, ...]         # rom_env variables a session refuses to run without
    consts: dict[str, tuple[str, int]]     # port-owned .const values (abi.CONSTS)
    labels: dict[str, str]                 # port-owned labels' defining files (abi.LABELS)
    kernal: dict[str, int]    # KERNAL addresses, fixed by the ROM, not the game
    cycles_per_second: int    # the CPU clock a snapshot's MAINCPU counts
    crash_entries: tuple[int, ...]   # KERNAL code that only runs on a crash or reset
    rom_status: str           # how a crash entry is told from banked RAM code: "port01" | "ted" | "mmu"
    screen_bank: str = "ram"  # VICE monitor bank holding the text screen
    screen_const: str = "SCREEN_RAM"   # the ABI constant giving its address
    screen_cols: int = 40
    map_bank: str = "ram"     # VICE monitor bank holding MAP_BASE
    # "kernal": write the key to the KERNAL keyboard buffer at the input stop.
    # "return": return it through the key routine's own exit (``sta igk_key``
    # in its wait loop, Game.key_stops), for a port that scans the keyboard
    # matrix itself and has no buffer to write.
    key_feed: str = "kernal"
    key_entries: tuple[str, ...] = ("input_get_key",)   # every routine that waits for a key
    # Memory a VICE snapshot leaves out, saved beside it and written back on
    # undump: x128's snapshot has no VDC module, and a restored C128 showed
    # (and would read back) the VDC's power-on pattern.
    snapshot_banks: tuple[str, ...] = ()
    # The colours of the screen, for the dashboard's live view, which draws
    # C64 colour indexes: the bank and ABI constant of the port's colour
    # memory, and the game's own table from C64 index to native colour
    # (inverted at boot), with the bits of a native value that are colour.
    color_bank: str = "io"
    color_const: str = "COLOR_RAM"
    color_table: str = ""     # empty: colour memory holds C64 indexes
    color_mask: int = 0x0F
    snapshots: bool = True    # the emulator can save and restore a machine mid-game
    # MAME ports (mame.py): the machine, the disk option, RAM the bridge reads
    # by name (MORIA8_BRIDGE_ITEMS) and the driver's banks in it, the key
    # wait's read taps (kind, address, buffer label: mame_bridge.lua), the
    # bytes the key wait pushes before it polls, and the screen's decoder.
    backend: str = "vice"
    mame_machine: str = ""
    mame_media: str = ""
    mame_items: str = ""
    mame_boot: str = ""      # typed after start (MORIA8_BRIDGE_BOOT)
    mame_banks: tuple[tuple[str, str, int], ...] = ()   # driver bank -> (bridge space, offset)
    key_taps: tuple[tuple[str, int | str, str], ...] = ()   # address: a number or a label
    key_wait_pushes: int = 0
    key_wait_end: str = ""    # the label just past input_get_key: the taps' PC window ends there
    screen_decoder: str = ""
    symbols: str = "main.vs"  # in build/<out>/

    @property
    def map_scale(self) -> float:
        """The level's area against the C64's 80x48: 1 on the 40-column ports,
        3.4 on the 80-column ports' 198x66 (Umoria's own size)."""
        return self.consts["hal_layout_map_cols"][1] * self.consts["hal_layout_map_rows"][1] / (80 * 48)
    key_map: str = ""         # mame.KEY_MAPS: the native key for the brain's PETSCII; "" feeds it as is


C64 = Port(
    name="c64", emulator="x64sc", out="c64", program="moria8.prg", disk="moria8-c64.d64",
    disk_target="disk64",
    disk_files={
        "moria8": "boot.prg", "boot64": "boot.prg", "bootart64": "bootart64.prg",
        "moria64": "moria8.prg", "t64": "title",
        **{f"monster.db.{tier}": f"monster.db.{tier}" for tier in range(1, 5)},
        **{f"64.{name}": f"ovl.{name}" for name in
           ("start", "town", "death", "modal", "gen", "help", "ui", "items", "spell", "chest")},
        "64.bank": "64.bank",
    },
    # Pinned machine configuration (§6.1). REU is mandatory: without it every
    # overlay switch and tier crossing reloads from the 1541.
    resource_args=(
        # +saveres is required: without it VICE tries to save resources through
        # GTK on exit and aborts when no display connection is available.
        # VICE_CONFIG stands for a per-worker config naming the installed VICE
        # version: an empty one (/dev/null) made VICE pop up "No version tag
        # found in config file" on the desktop for every instance.
        "-default", "-config", "VICE_CONFIG", "+saveres",
        "-console", "+sound", "-sounddev", "dummy",
        "-warp", "-pal", "-seed", "1",
        "-reu", "-reusize", "512",
        "-drive8type", "1541", "-drive8truedrive",
    ),
    # Optional ROM images, from the caller's environment only (AGENTS.md rule
    # 9): a KERNAL and a 1541 drive ROM, e.g. JiffyDOS's pair, which only works
    # as a pair. Unset: VICE's own ROMs. Any other ROM option can be played the
    # same way (maintainer, 2026-10-27).
    rom_env=(("PLAYTEST_KERNAL", "-kernal"), ("PLAYTEST_DOS1541", "-dos1541")),
    required_roms=(),
    consts={
        "SCREEN_RAM": ("platforms/commodore/c64/memory.s", 0x0400),
        "COLOR_RAM": ("platforms/commodore/c64/memory.s", 0xD800),
        "MAP_BASE": ("platforms/commodore/c64/memory.s", 0xC000),
        **{name: ("platforms/commodore/c64/hal/layout.s", value) for name, value in (
            ("hal_layout_map_cols", 80), ("hal_layout_map_rows", 48),
            ("hal_layout_viewport_x", 1), ("hal_layout_viewport_y", 2),
            ("hal_layout_viewport_w", 38), ("hal_layout_viewport_h", 19),
            ("hal_layout_status_row", 21), ("hal_layout_screen_rows", 25), ("hal_layout_input_row", 24))},
        "KBDBUF_COUNT": ("platforms/commodore/c64/input.s", 0xC6),
    },
    labels={"input_get_key": "platforms/commodore/c64/input.s",
            "input_get_command": "platforms/commodore/c64/input.s"},
    kernal={"KERNAL_KEYD": 0x0277, "KERNAL_JIFFY": 0x00A0},   # jiffy clock: 24-bit, big endian
    cycles_per_second=985248,   # PAL
    # The KERNAL's reset and RESTORE warm start. Banked RAM code can occupy the
    # same addresses ($F000-$FFFA), so a hit is a crash only when the KERNAL ROM
    # is visible ($01 bit 1, HIRAM, set).
    crash_entries=(0xFCE2, 0xFE66),
    rom_status="port01",
)

PLUS4 = Port(
    name="plus4", emulator="xplus4", out="plus4", program="moria4.prg", disk="moria8-plus4.d64",
    disk_target="diskplus4",
    disk_files={
        "moria8": "boot4.prg", "boot4": "boot4.prg", "moria4": "moria4.prg", "t64": "title",
        **{f"monster.db.{tier}": f"monster.db.{tier}" for tier in range(1, 5)},
        **{f"4.{name}": f"ovl.{name}" for name in
           ("start", "town", "death", "modal", "gen", "help", "ui", "items", "spell", "chest")},
        "4.bank": "4.bank",
    },
    # No REU: every overlay switch and tier crossing loads from the 1541, so the
    # Plus/4 plays under JiffyDOS (maintainer, 2026-10-27: "definitely use the
    # jiffydos kernal on plus/4, it's too slow otherwise").
    resource_args=(
        "-default", "-config", "VICE_CONFIG", "+saveres",
        "-console", "+sound", "-sounddev", "dummy",
        "-warp", "-model", "plus4pal", "-seed", "1",
        "-drive8type", "1541", "-drive8truedrive",
    ),
    rom_env=(("PLAYTEST_PLUS4_KERNAL", "-kernal"), ("PLAYTEST_DOS1541", "-dos1541")),
    required_roms=("PLAYTEST_PLUS4_KERNAL", "PLAYTEST_DOS1541"),
    consts={
        "SCREEN_RAM": ("platforms/commodore/plus4/memory.s", 0x0C00),
        "COLOR_RAM": ("platforms/commodore/plus4/memory.s", 0x0800),
        "MAP_BASE": ("platforms/commodore/plus4/memory.s", 0xC800),
        **{name: ("platforms/commodore/plus4/hal/layout.s", value) for name, value in (
            ("hal_layout_map_cols", 80), ("hal_layout_map_rows", 48),
            ("hal_layout_viewport_x", 1), ("hal_layout_viewport_y", 2),
            ("hal_layout_viewport_w", 38), ("hal_layout_viewport_h", 19),
            ("hal_layout_status_row", 21), ("hal_layout_screen_rows", 25), ("hal_layout_input_row", 24))},
    },
    labels={"input_get_key": "platforms/commodore/plus4/input.s",
            "input_get_command": "platforms/commodore/plus4/input.s"},
    # The Plus/4 KERNAL's keyboard buffer and its count (NDX), and TIME.
    kernal={"KERNAL_KEYD": 0x0527, "KBDBUF_COUNT": 0x00EF, "KERNAL_JIFFY": 0x00A3},
    cycles_per_second=1773447,   # PAL, the TED's single-clock rate
    # The KERNAL's reset entry ($FFFC points at it). The game banks RAM over
    # the ROM at $8000-$FFFF, so a hit is a crash only when TED $FF13 bit 0
    # reads 1 (ROM selected).
    crash_entries=(0xFFF6,),
    rom_status="ted",
    color_bank="ram", color_table="plus4_color_attr", color_mask=0x7F,   # TED luminance and chroma
)

C128 = Port(
    name="c128", emulator="x128", out="c128", program="moria128.prg", disk="moria8-c128.d71",
    disk_target="disk128",
    disk_files={
        "moria8": "boot128.prg", "boot128": "boot128.chain.prg", "bootart128": "bootart128.prg",
        "moria128": "moria128.prg", "t128": "title",
        **{f"monster.db.{tier}": f"monster.db.{tier}" for tier in range(1, 5)},
        **{f"128.{name}": f"ovl.{name}" for name in
           ("start", "town", "death", "modal", "gen", "help", "ui", "items", "disarm", "chest")},
        **{f"128.{name}": f"128.{name}.prg" for name in
           ("input", "proj", "runtime", "fdisk", "diskio", "world", "item", "names", "huff", "hvec",
            "select", "persist", "play", "bank")},
    },
    # The shipping .d71 on a true 1571, the REU (preload128.s caches overlays
    # and tiers in it), and the VDC's 80-column screen.
    resource_args=(
        "-default", "-config", "VICE_CONFIG", "+saveres",
        "-console", "+sound", "-sounddev", "dummy",
        "-warp", "-pal", "-seed", "1", "-80col",
        "-reu", "-reusize", "512",
        "-drive8type", "1571", "-drive8truedrive",
    ),
    rom_env=(),
    required_roms=(),
    consts={
        "VDC_SCREEN_BASE": ("platforms/commodore/c128/screen_vdc.s", 0x0000),
        "VDC_ATTRIB_BASE": ("platforms/commodore/c128/screen_vdc.s", 0x0800),
        "MAP_BASE": ("platforms/commodore/c128/memory128.s", 0x4000),
        **{name: ("platforms/commodore/c128/hal/layout.s", value) for name, value in (
            ("hal_layout_map_cols", 198), ("hal_layout_map_rows", 66),
            ("hal_layout_viewport_x", 1), ("hal_layout_viewport_y", 2),
            ("hal_layout_viewport_w", 78), ("hal_layout_viewport_h", 19),
            ("hal_layout_status_row", 21), ("hal_layout_screen_rows", 25), ("hal_layout_input_row", 24))},
        "KBDBUF_COUNT": ("platforms/commodore/c128/input128.s", 0xD0),
    },
    labels={"input_get_key": "platforms/commodore/c128/input128.s",
            "input_get_command": "platforms/commodore/c128/input128.s",
            "input_get_key_fast": "platforms/commodore/c128/input128.s",
            "igk_key": "platforms/commodore/c128/input128.s"},
    kernal={"KERNAL_KEYD": 0x034A, "KERNAL_JIFFY": 0x00A0},
    cycles_per_second=985248,   # PAL; VICE counts 1 MHz cycles in 2 MHz mode too
    # The KERNAL's reset and NMI entries ($FFFC, $FFFA). A hit is a crash only
    # with the KERNAL ROM mapped: MMU configuration ($D500) bits 5-4 clear.
    crash_entries=(0xFF3D, 0xFF05),
    rom_status="mmu",
    screen_bank="vdc", screen_const="VDC_SCREEN_BASE", screen_cols=80,
    map_bank="ram01",   # docs/C128_MEMORY_CONTRACT.md: the map lives in Bank 1
    key_feed="return",
    # input_get_key_fast is its own wait loop (commands, modal dismissal),
    # with its own ``sta igk_key`` exit.
    key_entries=("input_get_key", "input_get_key_fast"),
    key_wait_pushes=2,   # X and Y, pushed before the wait loop where the driver stops
    snapshot_banks=("vdc",),
    color_bank="vdc", color_const="VDC_ATTRIB_BASE", color_table="vic_to_vdc_color",   # RGBI
)

APPLE2 = Port(
    name="apple2", emulator="mame", out="apple2", program="moria8a2.prg", disk="moria8-apple2.po",
    disk_target="diskapple2",
    disk_files={},   # ProDOS: launch.check_disk compares dates
    resource_args=(),
    rom_env=(("A2ROMS", "-rompath"),),
    required_roms=("A2ROMS",),
    consts={
        "SCREEN_RAM": ("platforms/apple2/memory.s", 0x0400),
        "MAP_BASE": ("platforms/apple2/memory.s", 0x0800),
        **{name: ("platforms/apple2/hal/layout.s", value) for name, value in (
            ("hal_layout_map_cols", 198), ("hal_layout_map_rows", 66),
            ("hal_layout_viewport_x", 1), ("hal_layout_viewport_y", 2),
            ("hal_layout_viewport_w", 78), ("hal_layout_viewport_h", 18),
            ("hal_layout_status_row", 21), ("hal_layout_screen_rows", 24), ("hal_layout_input_row", 20))},
    },
    labels={"input_get_key": "platforms/apple2/input.s",
            "input_get_command": "platforms/apple2/input.s",
            "igk_key": "platforms/apple2/input.s"},
    kernal={},
    cycles_per_second=1020484,
    crash_entries=(),   # a 65C02 has no JAM and the game owns the machine: hangs only
    rom_status="",
    screen_cols=80,
    map_bank="aux",     # docs/APPLE2_MEMORY_POLICY.md: the map is in aux RAM
    color_table="", color_bank="", color_const="",   # colourless: logical colours only
    snapshots=False,
    backend="mame", mame_machine="apple2ee", mame_media="-flop1",
    mame_items="main=:ram/0/m_pointer;aux=:aux:ext80/0/m_ram",
    mame_banks=(("ram", "main", 0), ("aux", "aux", 0), ("io", "cpu", 0)),
    # input_get_key polls the keyboard latch, after pushing X and Y.
    key_taps=(("latch", 0xC000, ""),),
    key_wait_pushes=2,
    key_wait_end="igk_key",   # input_wait_release follows and drains the latch too
    screen_decoder="apple2_80",
    key_map="apple2",
)

ATARI8 = Port(
    name="atari8", emulator="mame", out="atari8", program="MORIA8.RES", disk="moria8-atari8.atr",
    disk_target="diskatari8",
    disk_files={},
    resource_args=(),
    rom_env=(("ATARI8ROMS", "-rompath"),),
    required_roms=("ATARI8ROMS",),
    consts={
        "SCREEN_RAM": ("platforms/atari8/memory.s", 0x0800),
        "MAP_BASE": ("platforms/atari8/memory.s", 0xC100),
        **{name: ("platforms/atari8/hal/layout.s", value) for name, value in (
            ("hal_layout_map_cols", 80), ("hal_layout_map_rows", 48),
            ("hal_layout_viewport_x", 1), ("hal_layout_viewport_y", 2),
            ("hal_layout_viewport_w", 38), ("hal_layout_viewport_h", 19),
            ("hal_layout_status_row", 21), ("hal_layout_screen_rows", 25), ("hal_layout_input_row", 24))},
    },
    labels={"input_get_key": "platforms/atari8/input.s",
            "input_get_command": "platforms/atari8/input.s",
            "atari_kbdbuf_len": "platforms/atari8/input.s",
            "atari_kbdbuf": "platforms/atari8/input.s",
            "igk_save_x": "platforms/atari8/input.s"},
    kernal={},
    cycles_per_second=1773447,
    crash_entries=(),
    rom_status="",
    color_table="", color_bank="", color_const="",   # the RAM font's screen codes carry no colour
    snapshots=False,
    backend="mame", mame_machine="a800xl", mame_media="-flop1",
    mame_items="main=:ram/0/m_pointer",   # all 64 KB, the map under the OS ROM included
    mame_banks=(("ram", "main", 0), ("io", "cpu", 0)),
    # input_get_key polls its key buffer, filled by the keyboard IRQ with
    # normalised PETSCII (platforms/atari8/input.s): the brain's keys as they are.
    key_taps=(("buffer", "atari_kbdbuf_len", "atari_kbdbuf"),),
    key_wait_end="igk_save_x",
)

BBCMASTER = Port(
    name="bbcmaster", emulator="mame", out="bbcmaster", program="moria8.res.prg", disk="moria8-bbcmaster.ssd",
    disk_target="diskbbcmaster",
    disk_files={},
    resource_args=(),
    rom_env=(("BBCMROMS", "-rompath"),),
    required_roms=("BBCMROMS",),
    consts={
        "BEEB_CHAR_SHADOW_BASE": ("platforms/bbcmaster/memory.s", 0x3800),
        "MAP_BASE": ("platforms/bbcmaster/memory.s", 0x8000),
        **{name: ("platforms/bbcmaster/hal/layout.s", value) for name, value in (
            ("hal_layout_map_cols", 198), ("hal_layout_map_rows", 66),
            ("hal_layout_viewport_x", 1), ("hal_layout_viewport_y", 2),
            ("hal_layout_viewport_w", 78), ("hal_layout_viewport_h", 18),
            ("hal_layout_status_row", 21), ("hal_layout_screen_rows", 24), ("hal_layout_input_row", 20))},
    },
    labels={"input_get_key": "platforms/bbcmaster/input.s",
            "input_get_command": "platforms/bbcmaster/input.s",
            "beeb_kbdbuf_len": "platforms/bbcmaster/input.s",
            "beeb_kbdbuf": "platforms/bbcmaster/input.s",
            "igk_key": "platforms/bbcmaster/input.s"},
    kernal={},
    cycles_per_second=2000000,
    crash_entries=(),
    rom_status="",
    color_table="", color_bank="", color_const="",
    snapshots=False,
    backend="mame", mame_machine="bbcm", mame_media="-flop1",
    mame_items="main=:ram/0/m_pointer;sw45=:romslot4:ram/0/m_ram",
    mame_boot="*EXEC !BOOT\r",
    # MAME's 128 KB: main RAM, then the shadow RAM LYNNE at $8000 (the
    # character shadow, SCREEN_RAM); the romslot4 card holds sideways banks 4
    # and 5, the map in bank 5 (docs/BBCMASTER_MEMORY_CONTRACT.md).
    mame_banks=(("ram", "main", 0), ("lynne", "main", 0x8000), ("bank5", "sw45", 0x4000 - 0x8000),
                ("io", "cpu", 0)),
    screen_bank="lynne", screen_const="BEEB_CHAR_SHADOW_BASE", screen_cols=80, screen_decoder="rows24", map_bank="bank5",
    # input_get_key pushes X and Y, then polls its key buffer, which holds the
    # game's own key codes (the brain's PETSCII as it is).
    key_taps=(("buffer", "beeb_kbdbuf_len", "beeb_kbdbuf"),),
    key_wait_pushes=2,
    key_wait_end="igk_key",
)

CX16 = Port(
    name="cx16", emulator="x16emu", out="cx16", program="MORIA8.PRG", disk="cx16",
    disk_target="buildcx16",
    disk_files={},   # no disk: x16emu boots the build directory (-fsroot)
    resource_args=(),
    rom_env=(("X16ROM", "-rom"),),
    required_roms=("X16ROM",),
    consts={
        "MAP_BASE": ("platforms/cx16/memory.s", 0x2000),   # virtual: Banks 1-2 (x16.X16Monitor)
        **{name: ("platforms/cx16/hal/layout.s", value) for name, value in (
            ("hal_layout_map_cols", 198), ("hal_layout_map_rows", 66),
            ("hal_layout_viewport_x", 1), ("hal_layout_viewport_y", 2),
            ("hal_layout_viewport_w", 78), ("hal_layout_viewport_h", 18),
            ("hal_layout_status_row", 21), ("hal_layout_screen_rows", 24), ("hal_layout_input_row", 20))},
    },
    labels={"input_get_key": "platforms/cx16/input.s",
            "input_get_command": "platforms/cx16/input.s",
            "igk_char": "platforms/cx16/input.s",
            "cx16_testbench_enabled": "platforms/cx16/input.s",
            "input_get_key_testbench_resume": "platforms/cx16/input.s",
            "entry_bootstrap": "platforms/cx16/main.s"},
    kernal={},
    cycles_per_second=8000000,
    crash_entries=(),
    rom_status="",
    color_table="", color_bank="", color_const="",
    snapshots=False,
    backend="x16",
    screen_cols=80, screen_decoder="vera", map_bank="map",
    symbols="main.sym",
)

PORTS: dict[str, Port] = {port.name: port for port in (C64, PLUS4, C128, APPLE2, ATARI8, BBCMASTER, CX16)}

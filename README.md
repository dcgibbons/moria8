# Moria8 for the Commodore 64 and 128

This is a port of the rogue-like game Moria8 for the Commodore 64 and 128
platforms.

This game is written entirely in 6502 assembly language using the Kick
Assembler suite of tools.

Source code is organized into a number of small modules specific to a single
purpose to keep program structure clean and well organized. The main.s file
represents the main program file.

The program utilizes a BASIC stub program that runs the machine code that
follows it directly to ensure easy loading from disk. A cartridge version of the
program is also available.

Gameplay uses PETSCII character display only. The shipped boot/loading art uses
platform-specific pre-title assets: a bitmap boot-art image on C64 and a custom-
charset poster helper on C128.

This game is based upon the umoria version of the Moria game (which was
originally written in PASCAL for the VAX/VMS plataform). The source code for the
umoria project can be found at https://github.com/dungeons-of-moria/umoria and
the source code for the original VMS version in PASCAL is found at
https://github.com/dungeons-of-moria/vms-moria

Unlike the original Moria / umoria implementation, the C64 only has a 40 column
display so the game will target that screen resolution. On the C128, the game
can run in either 40 column or 80 column mode and it should be selectable.

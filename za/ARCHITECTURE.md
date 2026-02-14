* Leverage the C64/C128 KERNAL routines, but do not use any of the BASIC
  routines once the main program runs.

* Because we are not using BASIC after the initial loader, the assembly program
  can freely use any of the zero page space dedicated to BASIC as needed, but
  the program should be able to exit cleanly and return to BASIC if possible.

* Use the C64 memory map features to freely utilize the RAM behind the BASIC ROM
  for extra program space.

* Attempt to minimize any disk loading after the initial loading, if possibly. 
  If data will not fully fit into memory, then organize data so that loading is
  not necessary during a given dungeon level's play. For example, higher-level 
  monsters would only appear on lower level dungeons and would not need to be in
  memory at all in the town or higher levels.


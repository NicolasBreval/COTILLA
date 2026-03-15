# Vendored Lua

This folder is reserved for vendored Lua sources (recommended: Lua 5.4.x).

## Expected files

The build currently expects these files in this folder:

- lapi.c
- lauxlib.c
- lbaselib.c
- lcode.c
- lcorolib.c
- lctype.c
- ldblib.c
- ldebug.c
- ldo.c
- ldump.c
- lfunc.c
- lgc.c
- linit.c
- liolib.c
- llex.c
- lmathlib.c
- lmem.c
- loadlib.c
- lobject.c
- lopcodes.c
- loslib.c
- lparser.c
- lstate.c
- lstring.c
- lstrlib.c
- ltable.c
- ltablib.c
- ltm.c
- lundump.c
- lutf8lib.c
- lvm.c
- lzio.c
- lua.h
- luaconf.h
- lauxlib.h
- lualib.h

## Notes

- Do not compile Lua CLI files (`lua.c` and `luac.c`) for embedding.
- Build with `zig build -Dwith_lua=true` once sources are copied.

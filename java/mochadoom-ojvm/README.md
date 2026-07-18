# Mocha Doom OJVM adapter

This directory contains DoomDB's GPLv3-compatible database adapter for the
pinned Mocha Doom source in `third_party/mochadoom`.

The adapter is deliberately headless. It must never create an AWT window, open
an audio device, start a free-running desktop loop, call `System.exit`, or read
game data from an untracked host path. Public calls catch every `Throwable` and
return a fenced failure so the resident database worker can reconstruct state.

The first integration gate compiles and resolves the complete upstream class
graph, initializes its deterministic lookup tables, and verifies the pinned
Freedoom IWAD stored in `DOOM_ENGINE_ARTIFACT`. Engine construction and bounded
`new_game`/`step`/`frame` entry points follow in T12.M2.

Upstream Mocha Doom is GPLv3. See `third_party/mochadoom/LICENSE.TXT` and the
per-file notices. The adapter is distributed under GPLv3-or-later. Oracle
Database is a separately licensed runtime and is not redistributed here.

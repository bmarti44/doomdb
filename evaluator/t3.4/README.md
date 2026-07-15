# T3.4 independent acceleration/graph evaluator candidate

This evaluator is authored independently from production T3.4 SQL and remains
pending explicit user approval. It decodes the pinned WAD directly rather than
reading generated seed JSON or implementation materializations.

## Frozen production interface

- `DOOM_BLOCK_CELL(cell_id, block_x, block_y, world_min_x, world_min_y,
  list_word_offset)` uses row-major `cell_id = block_y * columns + block_x`.
- `DOOM_BLOCK_LINE(cell_id, line_ordinal, linedef_id)` excludes the leading zero
  and `0xffff` framing words while preserving list order and duplicate entries.
- `DOOM_SECTOR_REJECT(source_sector_id, target_sector_id, rejected,
  byte_offset, bit_offset)` contains every sector pair and a constrained 0/1 bit.
- `DOOM_SECTOR_EDGE(edge_id, source_sector_id, target_sector_id, linedef_id,
  sound_block, opening)` uses `edge_id = linedef_id * 2 + direction`, where zero
  is right-sector to left-sector and one is its inverse. Only two-sided,
  distinct-sector lines with positive static opening are eligible. `sound_block`
  is linedef flag `0x40`; parallel linedefs remain distinct edges.
- `DOOM_SECTOR_GRAPH` is an Oracle SQL property graph with `DOOM_MAP_SECTOR`
  vertices labeled `SECTOR` and `DOOM_SECTOR_EDGE` edges labeled `PASSABLE`.
  Production must consume it through `GRAPH_TABLE`, not merely create a
  graph-named view.

Cell membership comes from the native BLOCKMAP lists and is not recomputed by
geometric intersection. REJECT indexing is source-major, target-minor and
least-significant-bit first. Negative world-coordinate cell selection uses
mathematical `FLOOR((coordinate-origin)/128)`.

The mini fixtures intentionally include negative boundaries, shared and empty
block lists, asymmetric REJECT bits, a sound-blocking edge, a closed two-sided
line, a one-sided line, an isolated sector, and parallel graph edges.

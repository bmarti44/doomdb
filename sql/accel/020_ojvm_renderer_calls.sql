whenever sqlerror exit failure rollback

create or replace procedure doom_bsp_kernel_fill(p_payload in blob) as
language java name 'DoomBspKernelBench.renderTicZero(java.sql.Blob)';
/

create or replace function doom_bsp_last_render_ns return number as
language java name 'DoomBspKernelBench.lastRenderNanos() return long';
/

create or replace function doom_bsp_last_codec_ns return number as
language java name 'DoomBspKernelBench.lastCodecNanos() return long';
/

create or replace function doom_bsp_last_blob_ns return number as
language java name 'DoomBspKernelBench.lastBlobNanos() return long';
/

create or replace function doom_bsp_last_bsp_ns return number as
language java name 'DoomBspKernelBench.lastBspNanos() return long';
/

create or replace function doom_bsp_last_solid_ns return number as
language java name 'DoomBspKernelBench.lastSolidNanos() return long';
/

create or replace function doom_bsp_last_portal_ns return number as
language java name 'DoomBspKernelBench.lastPortalNanos() return long';
/

create or replace function doom_bsp_last_plane_ns return number as
language java name 'DoomBspKernelBench.lastPlaneNanos() return long';
/

create or replace function doom_bsp_last_sprite_ns return number as
language java name 'DoomBspKernelBench.lastSpriteNanos() return long';
/

create or replace function doom_bsp_last_presentation_ns return number as
language java name 'DoomBspKernelBench.lastPresentationNanos() return long';
/

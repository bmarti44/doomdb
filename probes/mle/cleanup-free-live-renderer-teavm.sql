whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off
begin execute immediate 'drop function doom_free_gen_screen';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_gen_menu_select';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_gen_menu';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_gen_title';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_gen_world';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_gen_world_geometry';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_gen_load_dynamics';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_gen_loaded_geometry';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_gen_world_sprites';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_gen_weapon';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_gen_status';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_gen_ui_finalize';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_gen_ui_load';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_gen_ui_allocate';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_gen_sprite_finalize';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_gen_sprite_load';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_gen_sprite_allocate';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_gen_raster_writes';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_gen_lit_chunk';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_gen_lit_length';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_gen_resolved_chunk';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_gen_resolved';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_gen_native_misses';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_gen_native_reset';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_gen_flat_finalize';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_gen_flat_load';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_gen_flat_allocate';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_gen_native_commands';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_gen_native_record_length';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_gen_native_chunk';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_gen_native_tape';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_gen_frame_chunk';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_gen_frame_batch';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_gen_frame';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_gen_frame_coarse';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_gen_live_coarse';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_gen_live_load';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_gen_live_loaded_coarse';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_gen_walls_only';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_gen_planes_only';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_gen_texture_finalize';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_gen_texture_load';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_gen_texture_allocate';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_gen_batch';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_gen_render';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_gen_finalize';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_gen_load';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_gen_allocate';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop mle module doom_free_generated_renderer';exception when others then if sqlcode not in(-4080,-4103) then raise;end if;end;
/
begin execute immediate 'drop table doom_free_generated_source purge';exception when others then if sqlcode<>-942 then raise;end if;end;
/
begin execute immediate 'drop mle module doom_free_live_compositor';exception when others then if sqlcode not in(-4080,-4103) then raise;end if;end;
/
begin execute immediate 'drop table doom_free_compositor_source purge';exception when others then if sqlcode<>-942 then raise;end if;end;
/

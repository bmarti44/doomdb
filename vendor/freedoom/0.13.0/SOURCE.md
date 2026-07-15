# Freedoom Phase 1 0.13.0 source record

The vendored archive is the `freedoom-0.13.0.zip` asset published with the
official Freedoom `v0.13.0` release:

- Release: <https://github.com/freedoom/freedoom/releases/tag/v0.13.0>
- Asset: <https://github.com/freedoom/freedoom/releases/download/v0.13.0/freedoom-0.13.0.zip>
- Archive SHA-256: `3f9b264f3e3ce503b4fb7f6bdcb1f419d93c7b546f4df3e874dd878db9688f59`
- `freedoom-0.13.0/freedoom1.wad` SHA-256: `7323bcc168c5a45ff10749b339960e98314740a734c30d4b9f3337001f9e703d`

`COPYING.txt`, `CREDITS.txt`, and `CREDITS-MUSIC.txt` are byte-for-byte copies
of the corresponding members in the archive. The WAD is intentionally verified
by extracting it from the pinned archive into a temporary directory; it is not
stored a second time.

Run `tests/verify-freedoom-vendor.sh` to verify the archive, extraction, WAD
hash and `IWAD` identification bytes without network access.

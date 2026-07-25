# DIAGNOSTIC long-flag cast benchmark — v3

Classification: `DIAGNOSTIC_WRAPPED_TERMINAL_NOT_GATE`.

All 20 alternating batches completed with equal checksums and measured a
3.2797x p50 advantage for the hoisted low-word shape. However, the SQL file
omitted `LINESIZE 32767`, so SQLcl wrapped the terminal marker across three
physical lines. Per the shared parsing contract, this run is not gate
evidence. The raw log is preserved and the `v4` rerun pins wide output.

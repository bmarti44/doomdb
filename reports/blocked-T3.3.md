# T3.3 evaluator correction resolved

Status: **resolved by the explicitly approved evaluator-only correction on
2026-07-14**.

The original bind-safety gap was corrected by adding the independently derived
`(792,64.25)` probe to `T33-BIND-SAFETY`. The unchanged fifteen-ID suite now
contains 455 assertions, and evaluator self-check contains 61 assertions.

On a fresh isolated Oracle Compose project, canonical production passed
455/455. The exact `T33-M12-ROUND-BINDS` production mutant then failed at the
intended assertion:

```text
ORA-20933: fractional bind subsector expected 157 got 558
PASS T33-M12-ROUND-BINDS (killed by T33-BIND-SAFETY fractional bind)
```

The canonical macro was restored and re-passed 455/455. The other fourteen
approved isolated semantic mutation kills retain their real execution evidence;
the correction did not change their assertion paths. The corrected approved
manifest SHA-256 is
`8ccb54c64ed3e4e34ec3e1f84cda03a3b3ebe4a7ec8bf26c5688ab0b96260e37`.


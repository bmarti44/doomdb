# Presentation pin lineage — 2026-07-24

Status: **verified decision record; no artifact rebuild or promotion performed**.

The presentation pin transition

```
d45863e0c1be8fabdc63086fafc5d9d57193c4ed5758f259cd92af360426b39c
  ->
e55d5f1138fa94d4fc7efd0acf27cbc89cb8a894e3d6828d84837a364b4426dc
```

is intentional and is not unexplained build drift.

`d45863e0…` was the 1,232,713-byte render-capable artifact paired with the
headless-authority init-diet promotion. Its promotion record binds it to input
adapter JAR `5194b73d7196804957221216052b552305632c943e8ea402327a220b326d0e06`
and Mocha bytecode
`42b25147133bb5c84c3b19c1511583bbd36219fb2a68996244106f40078f943e`.
It subsequently exposed an incomplete status-bar implementation in live
browser review.

`e55d5f11…` is the deliberate presentation-only replacement that restores
Mocha's full status-bar delegate, including ammo, health, armor, weapon and
ammo counters, and the animated face. The authoritative adapter source was
unchanged by this presentation decision. The replacement is 1,250,529 bytes
and is bound in `versions.lock` to:

- presentation input bytecode
  `595a9a39bafe3aa6e3bbd2405fb1ca17f3bfa081dbf098360503ba3ab32d859b`;
- presentation Mocha bytecode
  `bdef8440d129c3b1bd334c9ebe66c4d2d1f0d803939d9a1c29b7191c98b16bb3`;
- TeaVM 0.15.0, JavaScript/ES2015, ADVANCED, minified build settings;
- exact promoted output
  `e55d5f1138fa94d4fc7efd0acf27cbc89cb8a894e3d6828d84837a364b4426dc`.

The 96-tic semantic presentation gate produced 93 unique moving frames per
POV, retained zero next-tic world residue, and pinned the two complete-HUD
goldens:

- POV 0: `dd2e30a5ca3d0ecdfbce78bf82bdc03898bffc19d201e571fee769eea50bf032`;
- POV 1: `96882b5d2d1fceed8d83437b13f3976eec2c140ee2b3d8c2cbaada0af665a0af`.

The repository copies were re-hashed during this audit:

- `doom-mle-presentation-d45863e0c1be.js`: `d45863e0…`;
- `doom-mle-presentation-e55d5f1138fa.js`: `e55d5f11…`;
- current presentation Mocha JAR: `bdef8440…`.

TeaVM 0.15 does not produce byte-identical JavaScript across all otherwise
equivalent invocations, so source/toolchain provenance and the exact deployable
output pin are both required. Replacing `e55d5f11…` requires the presentation
semantic gate again; it is never inferred from the authority artifact pin.

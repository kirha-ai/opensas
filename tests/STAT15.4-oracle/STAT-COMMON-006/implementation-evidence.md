# STAT-COMMON-006 helper evidence

## Contract and sources

Read the [README](README.md), [original CLASS-order program](class_order.sas), [complete expected listing](class_order.expected.txt), [expected status](class_order.expected.rc), and [SAS log](class_order.oracle.log). The SAS/STAT 15.4 User's Guide, Chapter 20, **physical PDF pages 411–413** (printed 399–401), defines formatted level membership, numeric internal-value exceptions, ORDER=, optional missing levels, and exclusion for every declared CLASS variable. The manual was read from the primary checkout's `docs/SAS-STAT-15.4-Users-Guide.pdf`.

The new [class_levels.zig](../../../src/stat/class_levels.zig) owns only levelization and inline tests. No GLM parser, design, renderer, numerical solver, main, or root file is changed.

```zig
build(allocator, dataset, rows, column_index, options) !Levels
buildValues(allocator, values, column, options) !Levels
```

`rows` is one caller-selected analysis/BY slice. Options contain `order` (`data`, `internal`, `formatted`, `freq`), raw-missing include/exclude policy, an optional row inclusion mask, and optional nonnegative frequency counts. Counts are not precision weights; the caller applies PROC-specific truncation/exclusion. Zero counts exclude a row. Invalid counts/types/nonfinite numeric values return `ExecError`; the PROC caller supplies diagnostics.

`Levels.levels` contains `{value,label,frequency,first_row}`. `value` is the minimum raw representative within a formatted group. Labels retain significant leading blanks and remove trailing padding. `row_to_level` is aligned to the supplied rows and holds zero-based sorted indices or null for excluded rows. `reference(.first/.last/.{.label=...})` performs explicit reference selection without choosing a PROC default or coercing formatted labels. General-allocator callers use `deinit()`; all output strings and values are owned.

No cross-call/BY state is cached. Callers must construct the complete-case mask across **all declared CLASS variables**, including those absent from MODEL (physical p.413), plus response/effect requirements. The helper does not infer those analysis rules.

## Focused verification

Nine inline helper tests passed through an explicit importing harness (ten runner tests including its root). They cover:

- The original COMMON-006 A/B rows under both ORDER=DATA and ORDER=INTERNAL, with all 12 row-to-column mappings and explicit references.
- Every row of manual Tables 20.2 and 20.4: raw numeric values, `3.0`, `3.1`, excluded missing rows, and included missing levels.
- Exact unformatted numeric keys even when BEST12 display labels collide; explicitly attaching BEST12 then permits formatted grouping. Special missing values and signed zero have canonical typed identities.
- Formatted grouping under all four order modes, minimum-raw representatives, descending frequencies, and internal-value tie order.
- Significant leading character/format-label blanks, trailing-blank equality, raw-missing exclusion despite a nonblank format label, and nonmissing numbers formatted to blank labels.
- Isolated BY slices, caller masks, remapped row indices, input permutations, output ownership, empty results, invalid inputs, and every allocator-failure path.

Level indices, labels, counts, and reference positions use exact assertions. No statistical numeric tolerance or oracle-derived fitting constant is involved.

## Independent live SAS checks

Invented-data SAS 9.4 probes on 2026-11-25 confirmed details not fully discriminated by the original A/B fixture:

1. Numeric raw sequence `(3,2,1,4)`, with format `1,3='Z' 2,4='A'`, gives levels **Z A** for DATA and INTERNAL, **A Z** for FORMATTED, and **Z A** for FREQ with equal counts. This verifies minimum-raw representatives and internal tie order.
2. Character sequence `(z,a,z,a)`, formatted `z='A' a='Z'`, gives **Z A** for FREQ ties, rather than formatted label order.
3. Format labels `' A'` and `'A'` remain two levels. A numeric missing mapped to `'M'` is excluded by default, but a nonmissing zero mapped to a blank label remains included: six input rows produce four used rows and two levels.
4. Numeric values `(2,10,1)` under default FORMATTED order appear as **1 2 10** without an explicit format. Explicit BEST12 retains its actual formatted field padding; the helper does not strip leading bytes from level identity.

These probes validate the general level rules; they do not substitute for the original GLM model oracle.

## Integration and gate status

The helper's focused tests pass. **COMMON-006 is not DONE:** dev2 must integrate the helper into GLM, with dev6's numerical model path, and execute the unchanged `class_order.sas`. Acceptance compares the complete expected listing token-for-token (whitespace only normalized), requires CLI exit **0**, and requires no warning/error diagnostics. Checking only the Class Level Information table is insufficient: both model runs and all ANOVA/Type-I/Type-III fields must match.

The authoritative branch gate is run separately with direct subprocess status capture:

```sh
/Users/thomas/.local/share/zig-0.16.0/zig build gate -j2 --summary all
```

The final handoff records its exact SHA, direct exit code, complete unit-test count, corpus count, and programs count. Until dev2 imports the helper, that gate covers existing integrated code; the explicit harness supplies evidence that the new inline tests actually ran. No green gate is inferred from partial output.

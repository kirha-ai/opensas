# STAT-COMMON-007 implementation evidence

## Sources and implementation boundary

Read the [README](README.md), [original effect-design program](effect_design.sas), [complete expected listing](effect_design.expected.txt), [expected status](effect_design.expected.rc), and [SAS reference log](effect_design.oracle.log). Manual sources are SAS/STAT 15.4, Chapter 20, **physical PDF pp.414–418** (printed 402–406), and GLMMOD declarations/output metadata in Chapter 54, **physical pp.4236–4241** (printed 4224–4229), read from the primary checkout's manual.

[design_matrix.zig](../../../src/stat/design_matrix.zig) constructs full GLM-coded columns and returns the row-major matrix, retained input-row indices, CLASS maps, and per-column effect/level metadata. [glmmod.zig](../../../src/stat/glmmod.zig) parses GLMMOD and publishes OUTDESIGN/OUTPARM. The main change is only the GLMMOD dispatch branch; root exports/imports its module. Existing GLM inference design/parser files and PRINT functions are unchanged.

The matrix deliberately retains all CLASS levels and observed interaction combinations, even when intercept/main/interaction columns are linearly dependent. It does not substitute contrasts, omit reference levels, fit coefficients, or invert a matrix. Crossed and nested CLASS lists follow CLASS declaration order; nested factors vary slower, and rightmost factors vary fastest within each list. Continuous factors precede CLASS factors in names. Their model-wide first-appearance order canonicalizes commutative products (`z*x` then `x*z` is one effect). Column effect indices refer to the first source effect, not an index shifted by duplicate removal.

Supported production path: NOPRINT with OUTDESIGN/OUTPARM; one numeric response; CLASS main effects; crossed, nested, continuous, polynomial, and continuous-by-CLASS terms; bar expansion and @ degree limits; ORDER=; NOINT; PREFIX=; ZEROBASED; NAMELEN=; procedure-local FORMAT; existing DATA/WHERE selection. OUTPARM contains numeric `_COLNUM_`, character EFFNAME, and character CLASS fields, with blanks for uninvolved classes. OUTDESIGN retains response attributes and one numeric column per design column.

## Full original oracle and typed-field checks

The real CLI executed the **unchanged** original `effect_design.sas`, including its DATA steps, GLMMOD request, and both PROC PRINT calls. Actual/expected status was **0/0**, stderr was empty, and all **261 listing tokens** matched. Only whitespace was normalized; no digits, labels, rows, or columns were removed and no numeric tolerance was applied. The existing COMMON-006 `class_order.sas` also matched all **228 tokens**, with exit 0 and empty stderr, preserving the separate GLM inference path.

The original creates OUTPARM with **15 rows / 4 columns** and OUTDESIGN with **12 rows / 16 columns** (response plus 15 design columns). An inline GLMMOD test independently checks every typed OUTPARM field, including each blank CLASS cell, every design matrix cell, response passthrough, column numbering, and canonical effect names. This prevents whitespace normalization from concealing a value in the wrong CLASS metadata column.

The exact column sequence is: intercept; two group indicators; three h indicators; six group-by-h indicators; x; and both x-by-group slopes. Expected values in tests are derived from the original input and indicator definitions, never embedded in production code.

## Independent checks

Seven inline tests passed through an explicit importing harness (eight runner tests including its root):

- Manual main/interactions retain aliases: each CLASS indicator block sums to the intercept; the two class-specific slopes sum to x. Every crossed indicator is checked.
- Sparse NOINT design with observed cells A1, A2, B2 omits the unobserved B1 column and checks all nested/slope/polynomial cells.
- General `z*x*B*A(D C)` canonicalizes to `z*x*A*B(C D)`; all 16 parameter level tuples and all matrix cells are checked against the manual's indexing rule.
- `z*x x*z` deduplicates one effect while retaining distinct GLM aliases. Source-effect index mappings are checked after deduplication.
- Parser/publication tests cover polynomial bar expansion, ORDER=DATA, CLASS reordering, NOINT, PREFIX/ZEROBASED numbering, and failures before any output dataset is published. Errors are captured diagnostics, not aborting child processes.

Separate invented-data SAS 9.4 runs on 2026-11-25 were compared against OpenSAS complete listings, all with exit 0 and empty stderr:

| Case | Full matching tokens | Discriminator |
|---|---:|---|
| sparse design | 76 | `b*a x(a) b(a) x*x / noint`, empty cell, missing x/y rows |
| continuous order | 39 | `z*x x*z g*z*x x*x*x`, canonical names and duplicate removal |
| zero-based prefix | 39 | PREFIX=X ZEROBASED changes both OUTPARM numbering and design names |
| explicitly assigned `b='.'` | 40 | a literal nonmissing period remains a CLASS level |
| explicitly assigned blank b | 28 | missing unused CLASS variable excludes the observation |

All matrix entries in these checks are integer products/indicators and use exact assertions. No source-specific or unrounded fitting tolerance is needed.

## Known limits and isolated upstream discrepancy

Direct GLMMOD listing without NOPRINT, BY/FREQ/WEIGHT output roles, multiple dependent-variable missingness passes, CLASS TRUNCATE, and additional MODEL options are visible unsupported paths. Bar expansion beyond sixteen terms is guarded to prevent accidental exponential requests. Other parameterizations such as reference/effect contrasts remain outside this full-GLM-coded helper.

One initial invented missing-input probe used a bare `.` token for a character variable in list input. SAS made that character value blank, while the current OpenSAS DATA reader retained a literal period; consequently SAS retained three rows and OpenSAS four. That initial comparison **did not pass**. Two subsequent valid SAS/OpenSAS programs explicitly assigned `b=' '` or `b='.'` before DATALINES and demonstrated that GLMMOD excludes the blank and retains the literal period correctly. No rule was added to misclassify every literal period as missing, no existing DATA parser was changed, and no original oracle was edited. The complete-case core also excludes missing response/continuous values and every declared CLASS variable, even an unused CLASS variable.

## Reproduction and final gate

From the repository root:

```sh
/Users/thomas/.local/share/zig-0.16.0/zig build -j2
python3 - <<'PY'
from pathlib import Path
import subprocess
for ticket, case in [('STAT-COMMON-007','effect_design'), ('STAT-COMMON-006','class_order')]:
    base = Path('tests/STAT15.4-oracle') / ticket / case
    run = subprocess.run(['zig-out/bin/opensas', str(base)+'.sas'], text=True, capture_output=True)
    assert run.returncode == int(Path(str(base)+'.expected.rc').read_text()) == 0
    assert run.stderr == '', (ticket, run.stderr)
    expected = Path(str(base)+'.expected.txt').read_text().split()
    assert run.stdout.split() == expected, ticket
    print(ticket, len(expected), 'tokens: PASS')
PY
/Users/thomas/.local/share/zig-0.16.0/zig build gate -j2 --summary all
```

The production root imports the new module and tests. The final handoff records the exact committed SHA, direct gate subprocess exit code, full unit-test count, corpus count, and programs count. Partial logs or standalone-only results are not treated as an authoritative green gate.

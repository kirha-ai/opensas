# STAT-GLM-003 evidence

## Independently verified source

Source: **SAS/STAT 15.4 User's Guide**, Chapter 53, `docs/SAS-STAT-15.4-Users-Guide.pdf`.
Physical PDF pages are one-based (`PdfReader.pages[physical_page - 1]`); the printed
running headers were checked, rather than inferring page numbers from text position.

- **Physical 4092, printed 4080, MODEL Statement:** “You can specify only one MODEL statement”.
  This is a GLM declaration restriction, so a second MODEL is invalid input.
- **Physical 4110, printed 4098, Using PROC GLM Interactively:** “MODEL statement cannot be repeated”.
  The restriction is reiterated for interactive use; it is not a promised future
  multiple-model capability.
- **Physical 4095, printed 4083, MODEL SINGULAR=number:** the default is
  “approximately 10⁻⁹ on most machines”. This passage describes regression-rank
  checking in MODEL, not CONTRAST/ESTIMATE estimability options.

The supplied case, README, complete expected listing and reference log were read.
All assigned physical pages 4066–4067, 4092–4096 and 4107–4110 were read. Fresh
extractions of physical pages 4092, 4095 and 4110, including their headers and text
hashes, are retained in `.zig-cache/stat-glm-003-evidence/parser-source-verification.json`.

## Changes and red/green evidence

Only two authorized production hunks change in `glm_parse.zig`: default SINGULAR
1e-7 → 1e-9, and the duplicate-MODEL branch uses a located user ParseError instead
of marking a capability gap. SS1/SS3 output selection and SS2 logic are untouched.
No main/root, renderer, numerical kernel or design implementation changes are made.

The new tests first failed on the old code:

```
SINGULAR: expected 0.000000001, found 0.0000001
Second MODEL: expected no capability-gap marker, but gapHit() was true
```

After the isolated fixes, all six explicit GLM003 contract tests pass. The duplicate
MODEL check pins error status 1 using captured diagnostics. The rank test uses
x=(-1,-1,1,1), v=(-1,1,-1,1), z=x+1e-4*v. Since x'v=0, the normalized last pivot is
exactly `1e-8/(1+1e-8)`: it must be retained at the documented default, giving rank
3 and residual DF 1, and was excluded by the former 1e-7 default. This is an
observable estimation check, not merely a default-field assertion.

The isolated retry passed six contract tests plus four import/harness blocks.
Its passing log is `green-contract-tests-retry.log`; earlier red logs are retained
separately. An intermediate retry exposed only a new test's obsolete pre-SS1
message substring; that assertion now requires the current rank-deficiency gap
without changing runtime behavior. Final normal-gate evidence is reported at the
final rebased SHA, not inferred from these intermediate runs.

## Effect/design coverage

Tests are in `src/stat/glm_effect_tests.zig`, imported by the existing GLM test
module and therefore included in the normal gate.

- Three-level CLASS: every constructed contrast row is checked exactly. Explicit
  linear identities recover the three indicator columns, proving equality of
  model spaces. DATA versus INTERNAL order changes the reference position but
  preserves fitted cell means (9,2,5), SSE=6, rank=3, residual DF=3 and effect
  SS=148/3.
- Balanced 2×3 interaction: all twelve design rows and contiguous effect block
  widths (1,2,2) are checked exactly. Independent cell means (1,3,4,8,9,11), each
  replicated twice with residuals ±1, give SSE=12 and residual DF=6. Type I and
  Type III SS are (400/3,18,2/3), with effect DF (1,2,2).
- Continuous products: response/effect ordering and columns for x, z, x*x, x*z,
  and x*x*z are checked by exact dyadic arithmetic, including negative values.
- REF syntax, nesting, bars, and missing-cell Type III hypotheses retain explicit
  captured capability gaps. No test pretends these are implemented. Full GLM
  singular parameter/output design remains the separately owned COMMON007 path.

The fitted-value/SS tests use `3*gamma(32*n*p*p)*max(1,abs(reference))`, with
binary64 unit roundoff u=2^-53 and gamma(k)=k*u/(1-k*u). The operation envelope
covers the small two-pass projection fits, and the balanced contrast Gram
matrices have independently calculated infinity condition number 3. Bounds are
fixed from dimensions/conditioning, not measured differences. Matrix construction
and original listing comparison use exact equality.

## Original oracle including graphs

The unmodified `documented_feature.sas` passes independently before and after the
SS1 landing: expected/actual status 0/0, complete **671/671** listing tokens match.
Only whitespace tokenization is applied; no numerical tolerance, substitutions,
missing-field omission or table filtering is used. Default Type I **and** Type III
output is preserved. The original expected file is unchanged.

Three real SVG artifacts are required and validated: IntPlot (7 observations,
2 groups/cell-mean lines), SGSCATTER (13 observations) and FitPlot (13 observations,
101 fitted points, ordered finite mean-confidence and prediction bounds). The only
stderr lines permitted are the three native SVG-publication notes. Historical SAS
source-echo notes and PNG paths are not claimed to match OpenSAS's native diagnostics.
The statistical content and graph controls are exercised by the original five analyses.

Reproduce from the repository root:

```
zig build gate -j2 --summary all
zig build -j2
python3 tests/STAT15.4-oracle/STAT-GLM-003/verify.py
```

The ticket-specific verifier invokes the existing strict graphical/listing contract
for **GLM003 only**, with its own unchanged case and expected file. It preserves raw
stdout/stderr, token diff, expected-file hash, current OpenSAS identity and graph
inventory under `.zig-cache/stat-glm-003-evidence/verified/`. Final SHA/base, direct
exit status and gate counts are supplied in the delivery report. No board edits,
expected-output edits or pushes are performed by dev2.

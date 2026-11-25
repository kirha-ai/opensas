# GLM-001 integrated evidence

The unchanged GLM-001 `documented_feature.sas`, GLM-002
`documented_default.sas`, and COMMON-006 `class_order.sas` were read and run
individually. Original expected files are unchanged. Complete listing comparisons
use whitespace tokenization only: no numerical replacement, omitted fields,
tables, notes or runtime identity substitution.

Observed integration results before final rebase:

| Case | Expected/actual status | Exact tokens | Native graphs |
|---|---|---:|---:|
| GLM-001 | 0/0 | 671/671 | 3 |
| GLM-002 | 0/0 | 671/671 | 3 |
| COMMON-006 | 0/0 | 228/228 | 0 |

GLM stderr contains exactly three native SVG publication notes; COMMON-006 stderr
is empty. Historical SAS source-echo/session notes and PNG paths are not claimed
to be identical to OpenSAS's native SVG diagnostics. No errors are filtered out.

## Implementation and dependencies

New GLM modules separate parsing, row/design construction, numerical calls,
listing rendering and native graph rendering. Dispatch/root additions preserve
REG and TTEST and reuse the existing native graphics session. Main's optional
per-procedure title context is preserved and used when present.

The numerical dependency is dev6's `glm_fit.zig` (original commits 08dfacde,
27c5b872): scaled QR/rank fitting, sequential and partial model comparisons,
rank-difference effect DF and separate frequency/precision weights. The CLASS
dependency is dev4's `class_levels.zig` (bd0e07ee): formatted identity, raw numeric
ordering when unformatted, explicit ORDER policies and per-row level mappings.
There is no private duplicate levelizer in GLM. Explicit SGSCATTER is dev6's
e89c41c0 prerequisite, called with the native session even when ODS GRAPHICS is OFF.

GLM selects each response independently unless MANOVA missing mode is requested.
FREQ truncation/exclusion is distinct from positive precision WEIGHT selection.
Original observation numbers and IDs remain available. CLASS factors use
sum-to-zero contrasts for complete hierarchical factorial main effects and
interactions; raw numeric products implement polynomial terms. Arbitrary reference
cell dummy deletion is not used as a Type III test.

Supported defaults/options include DATA, ALPHA, NAMELEN, ORDER, MANOVA missing
mode, MULTIPASS (in-memory input), NOPRINT, PLOTS=NONE, CLASS, MODEL products,
BY/NOTSORTED/DESCENDING, FREQ, WEIGHT and ID. Missing/invalid variables and invalid
option values report located errors. Valid but unsupported OUTSTAT, CLASS
reference options, SOLUTION, nesting/nonhierarchical or mixed CLASS/continuous
interaction hypotheses, rank-deficient/empty-cell hypothesis presentation,
interactive continuation and other graph families remain explicit capability gaps.
Categorical NOINT is not represented by the contrast-design path; numeric NOINT
uses the numerical helper's no-intercept contract.

The complete originals contain all five required analyses: two unbalanced 2x2
factorial runs, two polynomial runs, and a linear regression. The COMMON-006
original covers CLASS ordering and additive adjustment by a numeric covariate.

## Independent checks

Inline GLM tests pin default/explicit settings and located failures, response-
specific versus MANOVA missingness, FREQ/WEIGHT separation, source observations,
blank ID preservation, BY group boundaries/sort failure, numerical NOINT and empty
input. The unbalanced design has cell means 13,10,19,17 and counts 2,2,2,1:
SSE=6, residual DF=3; Type I SS=(1681/21,169/15,2/5), Type III SS=(338/5,10,2/5).
Tests check the constructed contrast columns, ranks and these independent values.

The numeric helper adds thirteen tests covering weighted/replicated fitting,
intercept control, rank-difference hypotheses, saturation and polynomial values.
The shared CLASS helper adds nine levelization tests. All imported helper and GLM
tests are reached by the normal gate, not only an isolated test harness.

Native GLM graphs are real data-driven IntPlot and FitPlot artifacts. The IntPlot
has seven observed points, two identified groups and four cell predictions. The
FitPlot has thirteen observed points and a 101-point polynomial curve with mean
confidence and individual prediction bands. An independent df=1 Cauchy critical
value, beta=(7/6,1/2), MSE=1/6 and covariance quadratic forms validate the band
calculation. SVG metadata retains raw coordinates, predictions and band limits.
SGSCATTER has thirteen original iron-data points and named axes/title.

All three SVGs were rasterized with rsvg-convert and visually inspected: axes,
titles, group identification, observed points, fitted lines and bands are readable
and unclipped. Their actual SVG bytes are preserved alongside this evidence.
The original WORK GPATH is /tmp; native graphics publication now opens an existing
directory first, so macOS directory symlinks are accepted without changing GPATH.
The original case exercises this path directly. New directories retain the existing
portable createDirPath behavior; failures remain visible.

## Reproduction and gate

From the repository root, with Zig 0.16.0:

```
zig build gate -j2 --summary all
zig build -j2
python3 tests/STAT15.4-oracle/STAT-GLM-001/verify.py
```

The verifier stores full stdout/stderr, exact token diffs, expected hashes,
per-case status and graph inventories. It asserts every listing token, every
unexpected diagnostic, graph counts and data points. Listing tolerance is zero.
The IntPlot numeric metadata check uses 128*machine-epsilon*max(1,|cell mean|),
not a rounded listing target; complete printed statistics remain exact.

Pre-rebase integrated gate: 1714 tests, 2306 corpus, 11 programs passed.
The final direct-exit gate, rebased SHA/base and original-case reports are supplied
in the delivery message. No expected-file edits, board edits or pushes by dev2.

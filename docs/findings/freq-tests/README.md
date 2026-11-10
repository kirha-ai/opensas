# FEAT-freq-tests — public PROC integration

Integrated on dev4 from local feat/stat/batch-1 at 6fc6373. The table dependency
has landed. Public parsing, table projection, execution and listing are wired;
EBNF now marks the supported inference surface. This is the fifth/final ticket,
not a new FREQ table or exact-statistics project.

## Surface inventory

- One-way equal-proportion GOF, TESTP/TESTF lists and secondary datasets, optional
  LRCHI, positive DF overrides and negative adjustments. Expected-value columns
  follow the analysis-level order, including ORDER=DATA, and respect NOPERCENT,
  NOCUM, MISSPRINT and display-only MAXLEVELS. TESTP's column is hidden by
  NOPERCENT; TESTF's frequency column remains. Zero totals validate options but
  emit a no-positive-weights note, not statistics. A single category has default
  DF0/missing p; explicit DF0 is invalid.
- Contingency Pearson/LR/Mantel–Haenszel/2x2 continuity tests, signed Phi/V,
  contingency coefficient, automatic integer-count 2x2 Fisher, fractional-count
  Fisher omission with NOTE, sparse warning controls and DF/p-value reporting.
- All 13 association MEASURES, estimate ASEs and confidence limits, seven
  null-variance TEST requests and their aliases, plus polychoric/tetrachoric
  estimates, Wald/LR tests and ADJUST/CONVERGE/MAXITER controls. Explicit MEASURES
  implies 2x2 odds ratio/relative risks; TEST-only implication does not print them.
- TEST cardinality counts TABLES statements, not expanded requests. One TABLES
  implies its requested measures; multiple TABLES requires explicit activation.
  Duplicate TEST errors; empty TEST and TEST without TABLES warn.
- One-/two-/n-way tables, BY and strata, LIST-to-GRID fallback after statistical
  implication, CROSSLIST, missing controls, missing/zero/negative weights and
  zero margins. Frequency Missing appears with both the displayed frequency
  table and its statistical summary, matching SAS.
- Actual TABLE/RANK/RIDIT/MODRIDIT score arrays and SCOROUT. Numeric missing TABLE
  scores retain display fallback but invalidate MH and Pearson inference only;
  TEST PCORR is omitted and a warning explains why. RANK remains valid.
- TABLES NOPRINT retains statistics/SCOROUT. PROC NOPRINT computes and validates
  but suppresses all listing output, including TITLE/FOOTNOTE. Main dispatch
  stamps FREQ titles only around an actual body, so datasets/variables named
  NOPRINT cannot be confused with the procedure option.
- Secondary aliases: _TESTP_/TestPercent/Percent and
  _TESTF_/TestFrequency/Frequency (priority in that order). Values use ordered
  rows, not joins or BY matching. Datasets override same-kind lists in either
  order; repeated dataset references warn/ignore; conflicting secondary inputs
  or using DATA= itself error. Lists imply CHISQ; dataset-only references do not.

Remaining explicit gaps: AGREE/ALL/CMH, standalone EXACT and OUTPUT statistics
datasets. No output dataset is silently claimed. WARN=OUTPUT records a marker
only. Unsupported named families remain rc2, invalid syntax/options rc1.
Existing destination gaps PAGE/COMPRESS/CONTENTS remain table-layer owned.

## Ownership and contract

D-029: new statistical code lives in src/stat. freq.zig owns public parsing and
orchestration; freq_table.zig owns ordered typed levels, missing policy, sparse
counts and scores. freq_tests.zig owns pure kernels; freq_tests_parse.zig owns
statistical options; freq_tests_execute.zig adapts tables/secondary inputs and
validates; freq_tests_render.zig owns statistical listings. proc.zig only delegates
and updates its captured diagnostic regressions. main.zig changes only FREQ
listing title/footnote glue.

The adapter accepts row-major CountMatrix, supplied row/column scores and the
numeric_table_scores_valid flag; no score recomputation occurs there. Negative
weights never reach inference. Statistical analysis uses all eligible levels,
independently of display truncation. Default DF0 is distinct from invalid DF0.

## Independent evidence and reproduction

All data are synthetic. Manual: local read-only SAS 9.4 statistical procedures
reference, FREQ pp.113–127, 150–176. Reproduce with:
`/Users/thomas/sas/bin/sasrun /absolute/probe.sas -f text -o /absolute/probe.txt -l /absolute/probe.log`.
Use ODS GRAPHICS OFF for the server's graphics-directory restriction.

Retained SAS sources/results/logs:

- oracle: ordinal/nominal measures, seven null ASE tests, polychoric MLE, signed
  2x2 tests and risks, GOF. edges: ties, fractional counts, ADJUST, MAXITER=1 and
  zero margins. options/boundary: expected sources, DF and boundary estimates.
- poly-precision: same association data with explicit CONVERGE=1e-8. SAS then
  reports Wald Z=5.6278 and -8.0920, upper tetrachoric CL=-0.6713, exactly matching
  OpenSAS. SAS default stopping gives 5.6279/-8.0927/-0.6714; this is convergence
  tolerance, not a formula discrepancy. The corpus specifies the tight criterion
  and the unit regression checks both Z values to half the last printed digit.
  User CONVERGE/MAXITER semantics remain intact; no hidden forced refinement.
- expected-semantics/expected-precedence: list accumulation, dataset precedence,
  alias priority, absent datasets and deliberate invalid cases. test-semantics:
  TEST implication/cardinality, intentional duplicate/mixed-source errors.
- list-scores: LIST fallback, NOPRINT, explicit scores and SCOROUT. onelevel and
  zero-total retain manager evidence; their -options/-df probes pin validation
  precedence and intentional errors.
- included-missing-scores: N160 manager oracle. CHISQ66.1627/LR61.5626, missing
  TABLE MH/Pearson, RANK MH45.6487/Pearson.5358, Spearman Z8.0104/Gamma Z7.8220.
- cli-expected, cli-by_strata, cli-boundaries, cli-test_requests: exact public
  sources are tests/corpus/freq_tests_{expected,by_strata,boundaries,test_requests}.sas.
- cli-noprint: source tests/corpus/freq_tests_noprint.sas, zero SAS errors/warnings;
  suppressed PROC title/footnote, visible TABLES NOPRINT statistics, and ordinary
  listing with dataset/variable named NOPRINT.
- public-validation: exact negative corpus sources together with NOSYNTAXCHECK;
  DF0, invalid TESTP sum, repeated TEST and same secondary DATA= deliberately
  error. SAS supports AGREE/OUTPUT; OpenSAS deliberately retains those named gaps.

## Regression and golden policy

Fifteen public freq_tests_* fixtures cover the above paths. Goldens are committed
separately from implementation and cite these SAS oracles. Decimal fields of all
nine positive fixture groups were compared with retained SAS outputs; after
using poly-precision for association all agree. Fisher observed-cell counts
print as integers, as in SAS. Existing OpenSAS indentation,
page-free layout and repeated-header conventions are retained, rather than SAS
pagination. Errors/gaps have empty listing goldens and explicit rc assertions.
No existing corpus golden required changing. The former CHISQ and TEST captured
unit negatives now assert supported CHISQ and invalid unknown TEST respectively;
AGREE/ALL/CMH/EXACT and typo guards remain fail-loud.

Final acceptance requires a clean local rebase onto feat/stat/batch-1 and all
three gates (unit, corpus, programs). Manager owns landing, pushes and Jira.

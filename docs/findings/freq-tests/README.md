# FEAT-freq-tests — dev4 work in progress

Base: dev4 at c2e450c9dd5b80e4adbaf84bcab1f524e2c0a5f7 (parent bdfcd4f).
This is NOT ticket completion: GAP-freq-table-complete is pending. No proc.zig
integration is permitted until the manager releases that dependency. No EBNF
support marker is asserted before the public interpreter supports the feature.

## Table contract

`src/stat/freq_tests.zig` exposes `CountMatrix { rows: usize, cols: usize,
counts: []const f64, row_scores: ?[]const f64, col_scores: ?[]const f64 }`.
Counts are row-major. The table layer owns level ordering, formatted-level
aggregation, missing policy, strata, weights and numeric TABLE scores. Null
scores mean 1-based ordinal scores. Fractional counts remain fractional.

Kernels: `goodnessOfFit(counts, Expected, ?f64)`,
`contingency(allocator, matrix, ?f64)`, `association(allocator, matrix, alpha)`,
`nominal(allocator, matrix, alpha)`, `risks(counts_2x2, alpha)`, and
`polychoric(allocator, matrix, PolychoricOptions)`. Shared error set: diag.Error.
Expected is equal, proportions (sum 1 or 100), or frequencies (sum observed N).

`freq_tests_parse.zig`: `consumeTableOption` advances its token index to the NEXT
unconsumed token, or returns false without consuming an unrelated table option.
`parseTests` takes tokens after TEST and before semicolon. `implyTests` applies
SAS's single-TABLES-statement implication only. Options travel with each TABLES
request. TEST selection is procedure-wide. CL alone implies MEASURES; PLCORR
also implies MEASURES. TABLES NOPRINT suppresses frequency tables, not statistics.

`freq_tests_execute.zig`: `validateSecondarySources` enforces the procedure-wide
single secondary dataset and DATA= exclusion. `resolveExpected` accepts the
secondary Dataset looked up by the existing Library, in displayed level order.
Accepted numeric columns: _TESTP_/TestPercent/Percent and
_TESTF_/TestFrequency/Frequency. `execute` accepts Table {matrix, one_way,
negative_weights}, options, TEST flags, resolved Expected, and PROC NOPRINT.
It returns Report with optional GOF/CHISQ and WARN output indicator. Missing and
negative WEIGHT policies must be established by the table layer before calling.

`freq_tests_render.zig` formats typed results and has no table/parser ownership.
The parent supplies the existing table title and sample-size footer. One-way
TESTP/TESTF also require Test Percent/Test Frequency columns in the frequency
table; that hook is pending on the table layer. The renderer is not yet claimed
as a byte-for-byte integrated corpus fixture.

## Evidence

Manual: SAS/STAT FREQ pp. 113–127, 150–152, 159–176, extracted reference found at
/Users/thomas/Desktop/mac-upgrade-backup/repos/opensas-private/docs/sas94-procedures-statistical.txt
(the designated dev4 checkout lacks this ignored reference). Formulas are read
locally; no confidential data are used.

Reproduce each retained synthetic probe with:
`/Users/thomas/sas/bin/sasrun /absolute/probe.sas -f text -o /absolute/probe.txt -l /absolute/probe.log`.
ODS GRAPHICS OFF is necessary on this server to avoid its unwritable image
output directory; the corrected oracle.sas run has zero errors/warnings.

- oracle.sas: 3x3 ordinal/nominal measures, seven TEST null SEs, joint polychoric
  MLE, 2x2 automatic Fisher and signed Phi/V, implied OR/RR limits, GOF LR/TESTP.
  The 3x3 polychoric result is 0.5906 (ASE 0.1049), LR 18.2978. Its Spearman
  estimate/ASE/null SE are 0.4769/0.1063/0.1079, proving that ordinary Pearson
  ASE applied to rank scores is not the correct FREQ Spearman ASE.
- edges.sas: tied lambda modes and ASEs; fractional weights (Fisher omitted with
  an explicit NOTE, NOT truncated); one-zero-cell ADJUST tetrachoric -0.9083;
  MAXITER=1 emits missing estimates and a nonconvergence note; zero margins
  suppress all statistics with the explicit zero-margin message.
- options.sas: secondary TESTP/TestFrequency datasets, legacy top-level TESTP,
  positive DF override, complete diagonal association and boundary tetrachoric.
  Live SAS overrides the manual's DF wording: Pearson/LR/continuity use DF=3,
  Mantel–Haenszel remains DF=1. Negative adjustment likewise leaves MH at 1.
- boundary.sas: unadjusted single zero gives tetrachoric -0.9990, ASE 0, missing
  Wald Z, LR 17.2930; complete independence gives tetrachoric 0, ASE 0.3512.
  Its final intentionally invalid DF=-1 case reports ERROR for nonpositive DF;
  this probe is expected to return an error, not a clean acceptance run.

All numeric oracle assertions use the half-last-displayed-digit tolerance
(0.00005 for four decimals). Exact Fisher's two-sided probability additionally
has a full-precision hypergeometric regression. Additional tests exercise input
validation, null-vs-estimate variances, ties, WARN routing and dataset aliases.

## Still required for full acceptance

Manager release of table dependency; integrated TABLES and TEST parsing and
execution; expected-value columns in one-way listings; integrated synthetic
corpus fixtures and separate oracle-backed golden commit; EBNF update; final
rebase onto feat/stat/batch-1 exactly once; all three final gates and landing
report. Neither this checkpoint nor passing kernel tests closes the ticket.

## First manager review correction: one observed category

The manager's freq-onelevel.sas/.txt/.log were copied verbatim as
onelevel.sas/.txt/.log. Three observations with g=1 and TABLES g/CHISQ
return SAS rc0 with CHISQ=0, default DF=0, missing p-value, and no warning.
The GOF kernel now permits this default case and represents the undefined
p-value as NaN in Test.p; rendering maps it to SAS missing (.). The execution
regression verifies no error/warning in both printed and PROC NOPRINT paths.

The independent onelevel-df.sas probe verifies LRCHI and TESTP=(100) also
return default DF=0/missing p without warning. Explicit DF=2 gives statistic0,
p=1, and a displayed sparse warning. Explicit DF=-1 reports nonpositive
adjusted DF; explicit DF=0 reports that DF must be nonzero. The probe's two
intentional invalid cases account for its sasrun exit2; neither is relaxed by
the default-DF exception. DF=0 default suppresses the sparse flag; valid
positive overrides retain the normal sparse computation.

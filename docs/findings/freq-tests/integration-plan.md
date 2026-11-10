# FEAT-freq-tests integration patch plan (dependency still pending)

Read-only snapshot of dev2's in-progress src/stat/freq.zig and
src/stat/freq_table.zig on 2026-11-10. No edits to dev2 or PROC dispatch.
Line locations below identify this snapshot, not a stable patch offset.

## Exact hooks after GAP-freq-table-complete lands

1. **Request and procedure state (freq.zig Request/Options, around 103/134).**
   Add `statistics: freq_tests_parse.Options = .{}` to each Request. Keep it
   nested: Request.expected is already the cell EXPECTED display flag, not
   the TESTP/TESTF ExpectedSource. Add procedure-wide TestStatement and a
   `tables_statement_count` counter. Increment only on a literal TABLE/TABLES
   statement, not each parenthesized/list expansion or default request.

2. **Option parser (Parser.tableOptions, around 285).** At the top of the
   option loop, before reading name and incrementing self.i, call
   `consumeTableOption(self.a,self.toks,&self.i,&req.statistics,self.diags)`;
   on true continue. Its index already points to the NEXT unconsumed token.
   Keep unrelated options and AGREE/ALL/CMH/exact gaps in the existing guard.
   Expanded requests copy the parsed statistics options with the rest of req.
   CHISQ and standalone TESTP/TESTF enter here. TESTP/TESTF lists imply
   CHISQ; dataset references alone do not. Repeated lists accumulate. A
   dataset overrides same-kind lists in either order; a second dataset
   reference in the same statement warns and is ignored.

3. **TEST parser (runFreq statement loop, around 413).** Before the existing
   exact/output/test gap guard, consume TEST through its semicolon and pass
   only its option tokens to TestStatement.parse. A second TEST is an error,
   including when the first was empty. Empty TEST warns, not errors. After
   parsing all statements call finish(actual_table_statement_count,diags),
   then implyTests on each Request.statistics. TEST without TABLES warns and
   leaves ordinary default one-way requests intact. Do not reinterpret the
   generated default requests as explicit TABLES statements.

4. **Secondary input resolution (after parse, before BY execution).** Validate
   all Request.statistics via validateSecondarySources using the RAW DATA=
   dataset name (raw.name), before its filtered/formatted copies. For each
   source name use cx.lib.find and resolveExpected. Cache the ordered values;
   do not BY-group, sort, or match secondary rows by the analysis value. The
   number and total of expected values are checked per actual one-way table.
   Resolve named dataset existence even on two-way paths: SAS errors on an
   absent secondary dataset before table execution. Two-way TESTP lists invoke
   ordinary contingency CHISQ; their values do not replace independence
   expectations. Dataset-only syntax without CHISQ produces no expected-value
   columns or GOF tests. Gate those columns on active CHISQ, not source alone.

5. **One-way analysis projection (currently no equivalent of Slice.matrix).**
   Use tab.dimensions[0].levels in their existing order and tab.count(key).
   Retain every nonexcluded level, including /ZEROS levels with zero count;
   include missing levels only when tab.include_missing. MISSPRINT displays
   missing rows but must not include them in the statistical vector. Do this
   BEFORE MAXLEVELS truncation. Preserve level-key mapping for expected-value
   display. Do not send an empty/all-missing/all-zero-weight analysis to the
   GOF kernel as a user error; retain SAS's empty-table behavior. One positive
   category IS valid: statistic0, default DF0, missing p, no warning.

6. **One-way expected columns (renderOne, around 863).** Extend the render
   input with resolved expected values plus analysis-key mapping. TESTP adds
   Test Percent; TESTF adds Test Frequency. Missing rows excluded by MISSPRINT
   have missing expected values. Respect NOPERCENT/NOCUM/MAXLEVELS while
   preserving the full analysis vector. Existing formatting helpers remain
   the owner of level labels, widths, attached formats and cumulative columns.

7. **Two-way/N-way execution (runFreq around 484–518; renderTable 839–859).**
   Slice.matrix(a,req.scores) already returns correctly ordered row-major
   counts plus explicit row/column scores and the kept Level arrays. Its
   CountMatrix is a distinct Zig type from the kernel's CountMatrix; adapt by
   explicit field copy (rows,cols,counts,row_scores,col_scores), no recomputation
   or allocation. Preserve zero-margin levels: do not silently shrink to an
   apparently valid table. The execute adapter renders the no-statistics case.

   Statistical slicing MUST be outside the display-only `req.list` early
   return. LIST and CROSSLIST still get per-stratum tests. Skip absent strata
   and missing CONTROL levels unless /MISSING: Slice.excluded currently tests
   only the last two dimensions, so the caller must also test controls.
   MISSPRINT must not enable tests on an excluded missing control stratum.

8. **NOPRINT/negative control flow (runFreq line ~514).** Replace the early
   `if (!any or opts.noprint or req.noprint) continue` with distinct table
   display and statistical execution decisions. TABLES NOPRINT still prints
   requested statistics; PROC NOPRINT computes but suppresses all listing
   output and routes sparse WARN to log. Pass only PROC noprint to execute.
   Empty data still bypass analysis. The parent already emits a negative-
   weight note; matrix returns null on negative weights, so skip statistical
   calls without a duplicate note (do not replace null with a zero matrix).

9. **Headings and footers.** Reuse the level/stratum identity from tableHeading
   (around 1040), giving each block its Statistics for Table heading and
   controlling values even with TABLES NOPRINT. Append Sample Size and Frequency
   Missing at the correct end, once. Do not interleave all display tables and
   then all tests for GRID/CROSSLIST; preserve table/stratum adjacency. LIST's
   aggregate display needs a following sequence of identified statistic blocks.
   Reconcile existing per-display missing footers explicitly, not by duplicating
   them. The adapter currently renders statistical bodies only.

10. **Output marker.** Report.warning carries WARN=OUTPUT for integration with
    a supported OUTPUT CHISQ request. Existing OUTPUT remains fail-loud until
    its named statistics/data schema are implemented; do not claim a silently
    missing dataset. WARN=OUTPUT alone does not create an output dataset.

## Acceptance fixtures once the hooks are live

- One-way equal/TESTP/TESTF, lists and all secondary column aliases, ORDER=DATA
  and formatted order, one category, zero-weight categories, DF overrides/errors.
- Single TABLES with multiple expanded requests versus two TABLES statements;
  all TEST aliases, duplicate TEST error, empty/missing-TABLES warnings.
- CHISQ with automatic 2x2 Fisher, signed Phi/V, fractional-weight Fisher note,
  sparse warning boundary/controls; TABLES NOPRINT versus PROC NOPRINT.
- All 13 MEASURES with CL/ALPHA, seven null-variance TESTs, implied OR/RR;
  PLCORR/ADJUST/CONVERGE/MAXITER and nonconvergence note/missing results.
- BY, strata, LIST/CROSSLIST, MISSING versus MISSPRINT, zero margins, negative
  and missing weights, MAXLEVELS display-only truncation, numeric/rank scores.
- Keep AGREE/ALL/CMH and unrelated exact requests as explicit gaps.

Only after integration: update EBNF support/tracker, add SAS-backed corpus
fixtures, commit expected outputs separately, rebase at report time as directed,
run all three gates, report final acceptance. Ticket remains DOING.

## Targeted TEST/option oracle audit

`test-semantics.sas` verifies two Gamma tests for one TABLES statement with two
requests, but just the explicitly enabled request for two TABLES statements.
It verifies that TABLES NOPRINT still displays tests; top-level TESTP alone
implies CHISQ; repeated TEST and mixed TESTP+TESTF are errors; empty TEST and
TEST without TABLES are warnings. Its two deliberate errors and two warnings
explain sasrun exit2. The isolated parser now exposes TestStatement.parse/finish
so these cardinality/warning rules do not have to be reimplemented by the parent.

The expected-semantics and expected-precedence probes further discriminate:

- Top-level TESTF lists imply CHISQ, as TESTP lists do. Dataset-only TESTP
  does not imply CHISQ. Explicit CHISQ activates that secondary input.
- TESTP=(20 30) followed by TESTP=(50) accumulates the values. Two complete
  lists accumulate to an invalid sum, rather than replacing the first list.
- _TESTP_ wins over TestPercent and Percent when all three are present.
- A dataset wins over same-kind literal values in either order: differing
  input vectors distinguish the resulting chi-square 8.1071 from 8.4000.
- A repeated dataset reference within one TABLES statement warns and ignores
  the second. Different secondary datasets across TABLES statements error.
- Two-way TESTP lists invoke ordinary contingency statistics; an absent
  secondary dataset errors even for a two-way request.

The parser regression covers implication, accumulation, same-family dataset
precedence and repeated-reference warnings without any PROC integration.

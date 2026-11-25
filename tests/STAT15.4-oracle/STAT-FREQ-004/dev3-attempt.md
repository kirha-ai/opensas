# STAT-FREQ-004 — exact comparison fields and oracle verification

Starting base: `69ea3f3d8048cc3b3d0c27206480678bc3187b03`; branch `codex/stat-dev3`.
Read this ticket's full stat-jira.md entry, README and all listed cases (one), manual physical
pages 3085–3094 and 3234–3238, and page 3269 for the fixture's preceding FORMAT definitions.
No oracle input/expected/reference files were changed. No shared files, board, or skill edits.

## Reproduce and retain actual results

After building OpenSAS, from the repository root:

```sh
python3 tests/STAT15.4-oracle/STAT-FREQ-004/verify.py --output /absolute/fresh/output-directory
```

The script discovers every SAS case listed in this README, runs it unchanged, and saves full
stdout, stderr, return status, graphs (if any), and a compact manifest. It exits nonzero on a
full-text/status/warning-error mismatch. The script also independently enumerates small exact
reference distributions and inverts the conditional odds distribution using Python Decimal.
`dev3-verification.json` records the checked input/output hashes and enumeration results;
final source SHA/base and exact-SHA gate counts are reported in the handoff.

Normalization is only `' '.join(text.split())`: collapse whitespace and trim edges. No fields,
tables, headings, rules, numerical values or diagnostics are removed. OpenSAS build identity
is retained; no SAS version string is substituted.

## Concrete baseline failures and corrections

Baseline status was 0, but its 239 tokens did not match the 263-token expected listing.
The existing numerical engine already computed the correct p-values and exact odds limits.

- Exact Pearson displayed only its exact p-value. It now also displays Chi-Square=4.9597,
  DF=1 and asymptotic p=0.0259, reusing the existing asymptotic report.
- Exact odds output omitted the odds estimate and asymptotic limits. It now displays
  OR=8.2500, asymptotic limits [1.1535,59.0029], and exact limits [0.8677,105.5488].
  These values use the existing risk and exact engines; no inference algorithm was replaced.
- Exact chi-square sections precede Fisher; the complete odds comparison follows the risk
  table. Automatic Fisher is deferred for display without discarding its computed result.
  Monte Carlo family order and shared random-number stream remain unchanged.
- Risk-table headings/rule and the displayed `(Asymptotic)` warning qualifier now match.
- Long row labels wrap at the default 16-character stub, retaining all text and cell values;
  continuation rows are retained even when a label needs more lines than its statistics.

Two focused unit regressions pin the complete exact comparison fields/section order and the
long-label/cell layout. The initial gate passed all 1613 unit tests and 11 programs but failed
12 corpus expectations affected by these deliberate listing changes (not a green gate).
Seven snapshot goldens and five assertion goldens were updated separately. Existing numerical
values are preserved; repeated confidence-level headings are consolidated. The OR assertion
now pins both asymptotic and exact limits rather than incorrectly requiring one limit pair.

## Complete oracle outcome

`documented_feature.sas`: expected/actual status **0/0**, complete **263/263-token match**.
The expected and actual listing both include the warning that 50% of cells have expected counts
below five and that the asymptotic chi-square might not be valid. It is a displayed footnote,
not a log warning. Actual stderr is empty; reference stderr warning/error semantics are also
empty. Informational SAS source echoes/read/page notes differ; no exemption is asserted.
Graphics are explicitly disabled; zero graphics were produced, so visual inspection is not
applicable. The manifest hashes cover complete output, not extracted statistical subsets.

## Independent exact checks and existing coverage

For cells [[11,4],[2,6]], fixed margins are rows [15,8], columns [13,10], N=23. Enumerating
X=5..13 yields integer weights [1287,17160,77220,154440,150150,72072,16380,1560,45]
with denominator 490314. Their sum is exactly 1. The observed mass is 2730/81719, left tail
162903/163438, right tail 545/14858; both Fisher and exact Pearson tails are 292/7429
(0.03930542468703729). Direct noncentral-hypergeometric tail inversion at 0.025 gives
[0.867737155043,105.548831004944], matching the displayed limits to four decimals.

The verifier additionally enumerates the tied zero-cell table [[0,5],[5,0]] (tied point mass
1/126), a single-outcome degenerate margin law, and one-way [2,8] under probabilities [.3,.7]
(Pearson exact p=0.733172068). Existing exact-engine unit tests cover exhaustive small integer
Fisher masses/ties/tails, reciprocal and zero-cell odds limits, binomial boundary coverage,
zero margins/fractional-count applicability, invalid controls and MC/POINT/MIDP restrictions,
resource termination, and single-versus-multiple TABLES selection. These remain in the gate;
no unrelated performance or QA work was added.

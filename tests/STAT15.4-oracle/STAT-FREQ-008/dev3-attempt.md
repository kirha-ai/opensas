# STAT-FREQ-008 — sensitivity/specificity verification

Result: existing implementation verified; evidence-only completion. No production, shared,
golden or regression changes. Starting base after fast-forward:
8b0bc8ca8a13106ad764aad4df9170150ab0dc48; branch codex/stat-dev3.
Read the full ticket, own README, all original/expected/status/log files, manual physical page
3188 and its referenced binomial Wald formulas on page 3180. Final SHA/base, direct-exit
`gate -j2` counts and completion time are in the handoff.

## Reproduce and retain actual results

```sh
python3 tests/STAT15.4-oracle/STAT-FREQ-008/verify.py --output /absolute/fresh/output-directory
```

The replay preserves complete stdout/stderr/status, all generated positive probe programs,
original-case SVGs, and a manifest. dev3-verification.json records the checked input/output
hashes, every actual diagnostic, exact proportion/variance fractions and unrounded reference
values. No fields, tables or numerical values are filtered. The only listing normalization is
whitespace runs/edges; numerical fields must match exactly at four displayed decimals.

## Original case and coverage

The ticket's unchanged original case independently passes all 649 tokens, status 0 and
warning/error comparison (none in actual or reference). Actual informational diagnostics are
three SVG-written notes. SAS source echoes, workspace/read/page notes differ; no informational
log exemption is claimed. Current OpenSAS version identity is retained.

The supplied original case does not request SENSPEC, so it is not used as sole feature proof.
Existing freq_risk_twoway_public.sas and freq_risk_strata_public.sas were also replayed unchanged;
their complete outputs match their goldens and both return 0. The latter includes its existing
NOTE about no valid displayed/output requests; this is retained in the manifest. These existing
regressions and the orientation unit test remain in the gate, so no duplicate regression was added.

## Independent conditional-proportion checks

For ordered cells [[a,b],[c,d]], the cited definitions are:

| Metric | Proportion | Conditional sample size |
|---|---|---|
| Sensitivity | a/(a+c) | a+c |
| Specificity | d/(b+d) | b+d |
| Positive predictive value | a/(a+b) | a+b |
| Negative predictive value | d/(c+d) | c+d |

ASE is sqrt(p*(1-p)/conditional_n), not based on the whole-table N. The verifier uses exact
fractions and 60-digit Decimal arithmetic, then independently applies the normal critical value
for the Wald limits. Unrounded references are retained; no blanket tolerance masks differences.
These are estimates and confidence intervals, so DF and null-test p-values are not applicable.

For [[12,8],[5,25]], N=50, the conditional denominators are 17,33,20,30. The complete rows are:

| Metric | Estimate | ASE | 95% lower | 95% upper |
|---|---:|---:|---:|---:|
| Sensitivity | 0.7059 | 0.1105 | 0.4893 | 0.9225 |
| Specificity | 0.7576 | 0.0746 | 0.6114 | 0.9038 |
| PPV | 0.6000 | 0.1095 | 0.3853 | 0.8147 |
| NPV | 0.8333 | 0.0680 | 0.7000 | 0.9667 |

Six independent positive probes check all four metrics and every SE/CI field:

- ORDER=DATA puts the explicitly first positive row/column levels first.
- Transposing the table swaps column-based sensitivity/specificity with row-based PPV/NPV.
- Default internal ordering puts the literal 'negative' level first; expected targets change
  accordingly. The engine must not infer positivity from a string label.
- ALPHA=.1 gives 90% intervals with unchanged estimates and SEs.
- [[5,0],[0,7]] produces four estimates of 1, ASE=0 and intervals [1,1].
- [[0,4],[6,0]] produces four estimates of 0, ASE=0 and intervals [0,0].

WEIGHT/ZEROS retains the declared event ordering even when its first cell has zero frequency.
All conditional denominators in these probes are positive. All six cases return 0 with empty
stderr. Boundary behavior follows the specified Wald method; no exact/Wilson substitution is
made. The six cases provide 96 independently checked numerical fields.

## Graphics

The original case's three fresh SVGs were rendered and inspected: boys/girls frequency plots
and the agreement plot. Bar counts [27,29,14,35] and [23,10,53,32] are also checked from SVG
attributes. Labels, category order, legends and axes agree with the data; agreement uses N=88.
No clipping/overlap was observed. Styling differs from SAS and pixel parity is not claimed.
SVG hashes preserve the inspected results reproducibly without duplicated listing/image dumps.

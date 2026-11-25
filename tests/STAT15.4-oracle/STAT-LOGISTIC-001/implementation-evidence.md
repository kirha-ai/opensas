# STAT-LOGISTIC-001 implementation evidence

## Scope and manual basis

Read the [README](README.md), both unchanged programs ([documented_feature](documented_feature.sas), [statement_by](statement_by.sas)), their complete expected listings, status files, and reference logs. S154 Chapter 79 physical **pp.5836–5851,5867,5901–5905** define the input roles/options and default graphics. Physical p.5840 specifies that an ODDSRATIO statement produces its confidence-limit plot when ODS Graphics is enabled; these programs request one such plot, or two in the explicit BY case. The additive and FREQ fits do not request additional default plots. Fitting/statistics use physical pp.5877,5883,5909–5918,5922.

The existing LOGISTIC modules now support events/trials input, positive truncated FREQ counts, positive analysis weights, BY slicing, validated ID declarations, continuous products/bar expansion, ODDSRATIO with one numeric AT variable/value list, ALPHA, and PLOTS=NONE. REF/EFFECT and explicit EVENT remain supported. Native odds-ratio SVGs use the existing graphics session; only an OddsRatioPlot identity was added to the shared graph enum. No main dispatch, PRINT, or GLM inference code changed.

STRATA/conditional models, WEIGHT NORMALIZE, BY with CLASS-global level complications, CLASS interactions, broader ODDSRATIO options, and other previously unsupported methods remain explicit gaps. This is not a full LOGISTIC coverage claim.

## Correct input and likelihood definitions

An aggregated binomial row is represented by **at most two** Bernoulli records, carrying event and nonevent frequencies. No memory expansion proportional to the trial count is used. Fisher scoring uses frequency times analysis weight in the score and information matrix. The original observation counts, frequency totals, and event counts are retained separately for display.

The fitting log likelihood is the Bernoulli-kernel likelihood, also obtained from the FREQ representation. The events/trials full log likelihood additionally includes

`sum(frequency * weight * (lgamma(n+1)-lgamma(r+1)-lgamma(n-r+1)))`.

Grouped output displays both covariate likelihood columns; FREQ output does not invent a grouped combinatorial term. SC and association denominators use the replicated trial count (387 here), not 19 grouped rows or 25 frequency records. Association counts frequency-weighted event/nonevent pairs, including within-cell ties.

The default optimizer now uses **relative ridging**, as specified on physical p.5883, rather than substituting step halving when a full step decreases likelihood. Diagonal penalties are implemented through augmented QR rows. An independent SAS ITPRINT run showed the first accepted relative ridge 0.0064 for the interaction example; independent matrix calculations verify that preceding smaller penalties still lower the likelihood. The implementation starts at 0.0001 and doubles adaptively; it contains no fitted-data shortcut. GCONV uses the documented denominator `abs(log_likelihood)+1e-6` (physical p.5877).

## Full original acceptance

The real CLI executed both original SAS files unchanged, including all analyses and explicit ODS GRAPHICS ON. `--graphics-dir` only isolates the artifact destination; no source options, data, expected results, or reference logs were modified.

| Original | Complete listing comparison | Actual/reference RC | Graphs |
|---|---|---|---|
| documented_feature.sas | **605/605 tokens**, exact after whitespace normalization | **0/0** | **1 odds-ratio SVG**, four AT rows |
| statement_by.sas | **826/826 tokens**, exact after whitespace normalization | **0/0** | **2 odds-ratio SVGs**, four AT rows each, separate BY labels |

Every model/profile/count, fit statistic (including full likelihood), LR/score/Wald test, coefficient/SE/p-value, association statistic, and odds-ratio/CI token is compared. No numeric tolerance is applied to the listing. Stderr contains only native `NOTE: SVG graphic written to ...` records (one or two respectively), with no ERROR/WARNING; these artifact notes are preserved rather than filtered and called empty diagnostics.

The COMMON-008 REF/EFFECT oracle is a regression requirement and remains an exact-token, RC=0, empty-diagnostics check with ODS Graphics off.

## Independent numerical and graphics checks

The focused LOGISTIC suite passes, including the previous REF/EFFECT invariance tests and two new checks:

- The 19 grouped rows are independently expanded to 387 unit-frequency Bernoulli observations. Coefficients/covariances agree within `1e-9`, likelihood within `1e-10`. The full-likelihood constant is independently computed as a sum of logs of finite products for binomial coefficients, rather than by the implementation's lgamma expression. The null likelihood is independently `12*log(12/387)+375*log(375/387)`.
- For `Heat*Soak`, the AT contrast is independently `[0,1,0,s]`; its variance is `V11+2*s*V13+s*s*V33`. All four log estimates and CI endpoints agree within `1e-12`.

All three generated SVGs were parsed as XML. Each contains four labeled AT rows and a reference line at OR=1. Every unrounded estimate/lower/upper data attribute agrees within `1e-9` with an independent NumPy binomial Fisher-scoring calculation on the original grouped counts, including adaptive relative ridging. This is independent of the compact Bernoulli/QR implementation. The plotted endpoints use a log axis. A rasterized BY plot was visually inspected: all labels, markers, intervals, axes, and the BY identifier are visible without overlap.

The only tolerances above concern independent floating-point calculations; none relaxes an original expected listing or substitutes rounded source values for fitting.

## Reproduction and final gate

From the repository root, choose an empty graphics directory for each original:

```sh
zig build -j2
zig-out/bin/opensas --graphics-dir /tmp/logistic001-main tests/STAT15.4-oracle/STAT-LOGISTIC-001/documented_feature.sas
zig-out/bin/opensas --graphics-dir /tmp/logistic001-by tests/STAT15.4-oracle/STAT-LOGISTIC-001/statement_by.sas
zig build gate -j2 --summary all
```

Compare the entire stdout token sequence with the corresponding unchanged `.expected.txt`, require direct RC=0, preserve informational SVG notes, and verify the one/two graph counts and all four data rows per graph. The final handoff records the exact commit/base, full test/corpus/program counts, and a directly captured subprocess exit code from the final gate. No pipeline-masked status or partial log is accepted as green.

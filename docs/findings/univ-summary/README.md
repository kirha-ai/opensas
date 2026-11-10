# GAP-univ-summary-complete — dev3 evidence and acceptance inventory

Base: bdfcd4f56fec199f65a859a5fccbd88eb58ca3ea. Worktree: opensas-dev3.
Reference: SAS 9.4 Statistical Procedures printed pp.299–306, 320–322, 342,
353–358, 408–414, 460–466. The supplied worktree has no extracted manual;
the read-only copy at opensas-private/docs/sas94-procedures-statistical.txt was used.

## Status: integration incomplete, not DONE

The summary implementation is in src/stat/univariate.zig. Existing UNIVARIATE
parsing/dispatch and listing remain in proc.zig with narrow calls into that module.
Shared helper implementations are reused through UnivariateHelpers.

**Blocking dependency:** unweighted OUTTABLE on nonconstant samples of at least
two observations requires `_NORMAL_` and `_PROBN_`. The baseline has no
normality computation. Real SAS populates these fields even without NORMAL.
The implementation reports a captured gap instead of inventing missing values.
The inference owner must supply the normality calculation before full OUTTABLE
acceptance and ticket closure. Weighted OUTTABLE and degenerate cases have
legitimately missing normality fields and are implemented. Optional inference/
robust OUTPUT keywords remain loud; their computation belongs to the inference
work, not this summary ticket. Internal robust formulas are available for
OUTTABLE's baseline fields.

## Surface inventory

| Surface | Implementation and validation |
| --- | --- |
| OUTPUT multiple name lists | Maps each name to its corresponding VAR; canonical SAS statistic order and labels; manager PCTLDEF4 probe gives 15,250,2.5,125. |
| Multiple OUTPUT statements | Distinct datasets; missing OUT names allocated without replacing existing DATAn. No _TYPE_/_FREQ_. |
| PCTLDEF 1–5 | Shared quantile kernel for fixed and arbitrary OUTPUT percentiles and listing. [0,10,20,30] P25 = 0,0,0,2.5,5. Weighted values ignore PCTLDEF. |
| PCTLPTS/PCTLPRE/PCTLNAME | Decimal/range lists, suffix fallback, prefix truncation to 32 characters. Omitted PCTLNDEC truncates at two decimal places; explicit PCTLNDEC rounds and caps at eight. PCTLGROUP defaults BYSTAT; BYVAR supported. |
| Metadata | Selected Summary Statistics label, percentile-definition dataset label, exact SAS OUTPUT labels/order; BY/CLASS/ID column attributes retained. |
| Summary keywords | NOBS, Q2, GEOMEAN, HARMEAN; weighted and missing counts; VARDEF=N skewness/kurtosis formulas; singleton MODE. |
| BY | Contiguous NOTSORTED groups remain separate; missing variable names error. |
| CLASS | One/two variables, per-variable MISSING and ORDER=DATA/FORMATTED/FREQ/INTERNAL; formatted level grouping; missing names error. |
| FREQ/WEIGHT | Truncated frequencies; aliases EXCLNPWGT/EXCLNPWGTS; BY, CLASS, ID, FREQ and WEIGHT removed from default VAR list. |
| ID/IDOUT | Physical source observation identities survive WHERE, FREQ, BY and CLASS. IDOUT uses first source observation of the BY group even when FREQ=0. |
| Extremes | NEXTROBS=0 suppression; counts above/below default; unique NEXTRVAL values; FREQ expansion does not duplicate physical extremes; lowest ties latest source first, highest displayed ascending with source-order ties. |
| MODES/FREQ display | All modes with counts, weighted frequency counts and percentages. Singleton MODE is the singleton value; unique multi-observation data has missing MODE. |
| ROUND | Ties-to-even, negative halves and decimal units, per-VAR units, rounding before summary calculations. |
| Empty input | Zero OUTPUT rows, schema retained. All-missing-weight CLASS groups omitted. |
| OUTTABLE | 48-column baseline schema including _VAR_ and _LABEL_; labels, _NOBS_ vs OUTPUT NOBS, _VARI_; weighted outputs tested. Unweighted normality dependency remains OPEN. |

## Oracle runs

All inputs are synthetic. Each `.sas` has a retained `.log` and `.txt` from
`/Users/thomas/sas/bin/sasrun INPUT -f text -o OUTPUT -l LOG`.

- `dev3-univ-probe`: ROUND, modes, ID/extremes, output metadata, full OUTTABLE
  schema and values, weighted/FREQ summaries. Confirms OUTTABLE normality
  fields are computed without NORMAL.
- `dev3-meta`: all summary keyword labels and canonical descriptor order;
  85.125/33.333 percentile suffix behavior and default BYSTAT ordering.
- `dev3-edge`: BY/CLASS/FREQ/WEIGHT, physical Obs=2/5 after WHERE filtering,
  zero-weight singleton, exclusion of all-missing-weight CLASS group, empty output.
- `dev3-zero` and `dev3-zero2`: all-zero-weight samples. SAS returns
  `(minimum+maximum)/2` for every weighted percentile, not missing; CSS=0.
  [0,10,20,100] yields 50 at 0/25/50/75/100. Singleton MODE=7.
- `dev3-idout`: first source ID A is retained even with its FREQ=0; both
  CLASS rows use A, not the first included observation or class representative.
- `dev3-summary`: regression fixture values; two VARs, multiple OUTPUTs,
  arbitrary percentiles, NOTSORTED repeated BY groups, VARDEF=N and means.
- `dev3-edges`: grouped physical extremes, weighted OUTTABLE, empty output,
  per-variable decimal rounding. DATA _NULL_ FILE PRINT values match exactly.
- `invalid-pctl`: missing PCTLPRE causes a real SAS ERROR, not an implementation
  gap. Existing rc_univ_outopt_gap now expects exit 1.

- `dev3-defaults`: numeric ID excluded from default analysis variables; weighted percentile OUTPUT dataset label is exactly `Selected Summary Statistics (Percentile Definition=Weighted)`.

Additional discriminating oracles:
- `dev3-name-explicit`, `dev3-ndec-range`, `dev3-pctlnames`: omitted PCTLNDEC
  truncates (85.1299 -> 85_12, 0.0099 -> 0_00); explicit PCTLNDEC=2 rounds
  (85.125 -> 85_13, 0.0099 -> 0_01). Values above eight are accepted but capped.
  Names retain only meaningful decimals on the explicit path.
- `dev3-collision`: colliding names produce warnings and retain the FIRST
  statistic/percentile, including its original label.
- `dev3-roundid`: ROUND changes extreme values, not the source ID values.
- `dev3-robust`: singleton robust scales are zero; zero-weight negative/zero
  values do not poison GEOMEAN/HARMEAN. Two distinct values have normality W=1,
  p=1, so the outstanding normality guard covers n=2 as well as larger samples.

## Golden change evidence

Expected files are committed separately from implementation. Differences follow
these observed SAS rules, not blanket acceptance of changed output:

1. Highest extremes display in ascending value order; lowest tied values use
   reverse source observation order; physical observation numbers survive filters
   and BY/FREQ. See dev3-univ-probe and dev3-edge.
2. OUTPUT uses canonical statistic column order independent of keyword order and
   records labels. See dev3-meta; dataset labels also confirmed by CONTENTS in
   dev3-univ-probe.
3. VARDEF=N skewness and kurtosis follow pp.411–412, corroborated by
   dev3-summary (`sk=0 ku=-1.36`).
4. Existing percentile and ID guards become successful regressions; missing
   PCTLPRE is a SAS input error. See the oracle runs above.
5. CLASS defaults ORDER=INTERNAL (printed p.321); formatted groups retain raw
   representatives and metadata. The old OUTPUT builder's formatted lexical
   row order was inconsistent with the listing and that documented default.

The repository's existing compact listing style is retained; new optional tables
use compact text layouts. SAS pagination and ODS appearance are not reproduced.

## Trackers

No new scalar SAS function is introduced, so sas-functions.md is unchanged.
sas9.4.ebnf explicitly excludes UNIVARIATE and other statistical procedures;
no unsupported whole-PROC marker was added. This inventory records the supported
summary grammar and the outstanding inference dependency instead.

## Intermediate landing

Manager authorized a green INTERMEDIATE landing with the normality guard. This
is not ticket completion. Dev1 is supplying `src/stat/normality.zig` with sorted
nonmissing FREQ-expanded input and optional statistic/p-value result; dev3 must
integrate it, remove the guard, and verify unweighted OUTTABLE including n=2,
constant samples, and the 2000/2001 switch before the ticket can become DONE.
The minimum normality fields are explicitly part of this ticket's prerequisite.

## Acceptance continuation after intermediate landing

- `dev3-large`: 5,003 observations, two analysis variables, all PCTLDEF values,
  arbitrary `alpha_`/`beta_` prefixes, and a FREQ/WEIGHT analysis containing 7,505
  expanded observations. All emitted value tokens match SAS exactly.
- `dev3-multigroup`: 20,012 physical observations, two BY groups, two crossed
  CLASS variables (one formatted), two analysis variables, IDOUT, FREQ and
  WEIGHT. Each analysis group has 5,003 physical / 7,505 expanded observations.
  Values and descriptor names/order/types/lengths/formats/labels match SAS.
  OUTTABLE orders rows by BY, then analysis variable, then CLASS combination.
- `dev3-classrep` and `dev3-classcross`: UNIVARIATE stores the FIRST INCLUDED raw
  value for a formatted CLASS level, shared across crossed levels and reset for
  each BY group. FREQ-excluded rows do not provide that representative. INTERNAL
  ordering uses this representative, not the lowest raw value. This corrects the
  earlier reuse of the MEANS/FREQ raw-minimum map; those procedures are untouched.
- `dev3-classvar`: SAS accepts the same numeric variable in CLASS and VAR. A
  separate analysis view preserves its numeric data while grouping uses formatted
  values. The sample [2,1] grouped into 'A' produces N=2, mean=1.5.
- Removed probe-specific `label()` branches identified by manager review;
  percentile labels are generated only by the generic percentile request path.

Additional OUTTABLE descriptor evidence:
- `dev3-emptytable` / `dev3-tablemeta`: no physical input observations yields a
  zero-column, unlabeled OUTTABLE. Nonempty input excluded by FREQ/WEIGHT/CLASS
  retains its descriptor. `_LABEL_` exists only when some analysis variable has
  a nonblank label and has fixed length 40 (long labels truncate). `_VAR_` is at
  least 8 characters and extends to the longest analysis variable name.
- `dev3-outtable-final`: complete normality/robust oracle at n=1,2,3,8,11,12,
  2000,2001,5003 and a constant sample, FREQ expansion across 2000/2001,
  weighted bypass, and empty input. Integration comparison follows support landing.

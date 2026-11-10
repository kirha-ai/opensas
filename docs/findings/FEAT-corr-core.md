# FEAT-corr-core — dev1

Base: bdfcd4f56fec199f65a859a5fccbd88eb58ca3ea. Worktree: opensas-dev1.
D-029: implementation in src/stat/corr.zig; main/root dispatch wiring; proc.zig
only makes existing numerical, BY, input-name, and parenthesis helpers public.

## Acceptance

- Pearson coefficient and two-sided Student-t p-value using pair N-2, evaluated
  directly through the shared incomplete-beta tail (avoids 1-CDF cancellation).
- Default simple statistics: N, weighted mean, sample SD, SUM (not median), min,
  max; N=0 gives missing statistics including sum. Constants have missing r/p;
  N=1 has missing SD/r/p, N=2 can have r but not p; diagonal p is not tested.
- VAR order, repeated VAR/WITH concatenation with deduplication, rectangular
  WITH rows / VAR columns; default numeric variables exclude BY/WITH/FREQ/WEIGHT.
  Named, numbered-range, name-range, prefix and _NUMERIC_ lists are supported.
- Shared WHERE/dataset input filtering without source mutation; shared BY
  scanner/grouping/sortedness/heading helpers, descending and NOTSORTED, last BY.
- FREQ truncates; <1/missing excluded. Missing WEIGHT excluded; negative weights
  become zero. Zero/negative weights count in N and min/max unless EXCLNPWGT.
  Effective weights are frequency times weight; df uses frequency counts.
- Pairwise missing deletion with pair-specific means and centered moments;
  NOMISS deletes over the selected VAR/WITH union. Special numeric missing values
  use the interpreter's common NaN representation.
- VARDEF DF/N/WDF/WEIGHT/WGT, COV/CSSCP/SSCP including pair-specific marginal
  sums/variances and divisor. NOPRINT/NOSIMPLE/NOPROB/NOCORR honored.
- Full precision typed Spec/Result/Group/Simple/Pair separate parsing/computation
  from rendering. Pair stores N, weight sum, both means, sums, raw and centered
  squares/crossproducts, divisor, covariance, marginal variances, r, p.
  Means are accumulated relative to the first positive-weight value to retain
  small spreads at large offsets. Regression compares translations by 1e12
  with spreads of 1/1024 against the original weighted data.

## Evidence and reproduction

Reference: SAS 9.4 Statistical Procedures printed pp.8–23,34–36. The untracked
reference was absent in dev1; read the same-named copy in opensas-private/docs,
not the manager checkout. No function tracker change: no SAS functions added.
EBNF has a separate proc_corr production.

Each retained FEAT-corr-core-*.sas was run with:

    /Users/thomas/sas/bin/sasrun /absolute/probe.sas -f text -o /absolute/probe.txt -l /absolute/probe.log

- `oracle`: 0 errors, one expected N=1 warning; supplied x/y gives r=.96204,
  p=.0001. Unequal missing/weights/frequencies: simple N(y,x,z)=(8,9,8),
  pair N(y,x)=7; y mean=3.875, SD=.83452; NOMISS N=5 all selected variables;
  EXCLNPWGT N(y,z,x)=(4,4,5). Tiny BY groups verify N=1,2,3.
- `precise`: OUTP read using DATA _NULL_ FILE PRINT gives r=.96204126289224,
  means (4.5,8.875), SD (2.44948974278317,4.94072001693217). OUTP is used
  only in the oracle; it belongs to the separate output ticket.
- `edge`: one intentional zero-total-weight error, later cases all visibly ran
  (retained complete log). Empty WHERE has no output; wholly missing x has
  N=0 and missing sum. VARDEF=N/WDF keep p=.1180. Overlapping WITH/VAR is deduped
  in simple statistics; negative perfect correlation verified.
- Isolated `freqzero`, `weightmissing`, `nomissnone`: each errors, respectively
  total frequency zero, total weight zero, or NOMISS with no complete observation.
  These were isolated so an error could not hide another case.
- `pairzeroweight`: succeeds when only a particular pair has zero weight:
  x N=2, sum=0, mean/SD/r missing; y N=3, mean=5, SD=0. Pair N=2.
- `lists`: repeated VAR/WITH append in order; FREQ=(2.9,1,3) gives N=6,
  x mean=3.33333, r=.99083, p=.0001 (versus .1210 without frequency).
- `filter`: corpus corr_filter_by.sas is the retained input. Combined dataset
  WHERE and statement WHERE gives descending groups 2,1; WITH y, default VAR
  x,z; group Ns 3,2. Later PROC PRINT proves source rows remain unchanged.
- `moments`: weighted x/y SSCP=(94,146,228), CSSCP=(13.33333333,21.33333333,
  35.33333333), covariance cross=10.66666667 at DF=2 and 4.266666667 at WDF=5.
  Missing rectangular case: SSCP/cross=86,rowSS=52,colSS=148; CSSCP=9,rowCSS=3,
  colCSS=27; covariance=3,rowVariance=1,colVariance=9,divisor=3,pairN=4.

## Rendering and scope

The core listing is a compact text presentation of the SAS-verified numbers,
not a claim of byte-for-byte SAS page layout. It always displays pair N and
uses a dash for an untested diagonal p. Moment tables explicitly expose each
pair's row/column marginals. Corpus goldens pin this compact layout, with the
numeric values independently checked by the oracle and unit assertions.
Advanced/rank/partial correlations, ALPHA/FISHER, OUTP and other output datasets,
and graphics remain separate tickets and fail visibly; they are not silently
accepted. No known in-scope numerical/selection gaps are deferred.

Fourteen new unit tests and seven corpus fixtures cover the behavior above.
Final post-rebase suite counts/exit codes are reported with the landing SHA.

/* GAP-gapsexitingone §5b re-verdict — `pctlpt=33` is not a documented
   PROC UNIVARIATE OUTPUT keyword (Table 4.14 + the percentile-options),
   so it is the USER's typo, exit 1. Gap twin: rc_univ_outopt_gap.sas.
   expect-rc: 1 */
data h;
  input x;
  datalines;
1
;
run;
proc univariate data=h;
  var x;
  output out=o pctlpt=33;
run;

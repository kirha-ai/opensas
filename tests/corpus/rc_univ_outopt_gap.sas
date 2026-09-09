/* GAP-gapsexitingone §5b re-verdict — PCTLPTS= is a documented PROC
   UNIVARIATE OUTPUT percentile-option (Statistical Procedures, OUTPUT
   Statement, printed pp. 356-358) opensas does not implement — an opensas
   gap, exit 2. Typo twin: rc_univ_outopt_typo.sas. expect-rc: 2 */
data h;
  input x;
  datalines;
1
;
run;
proc univariate data=h;
  var x;
  output out=o pctlpts=33;
run;

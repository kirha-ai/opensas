/* GAP-gapsexitingone §5b re-verdict — NORMAL is a documented SAS 9.4 PROC
   UNIVARIATE option (Statistical Procedures, PROC UNIVARIATE Statement
   dictionary, printed pp. 300-306) opensas does not implement — an opensas
   gap, exit 2. Typo twin: rc_univ_option_typo.sas. expect-rc: 2 */
data h;
  input x;
  datalines;
1
;
run;
proc univariate data=h normal;
  var x;
run;

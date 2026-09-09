/* GAP-gapsexitingone §5b re-verdict — an unknown PROC UNIVARIATE statement
   that is not the documented INSET gap is the USER's typo, exit 1. Gap
   twin: rc_univ_stmt_gap.sas. expect-rc: 1 */
data h;
  input x;
  datalines;
1
;
run;
proc univariate data=h;
  zzzq x;
  var x;
run;

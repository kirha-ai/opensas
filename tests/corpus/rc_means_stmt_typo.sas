/* GAP-gapsexitingone §5b re-verdict — an unknown PROC MEANS sub-statement
   that is not one of the documented ATTRIB/LABEL gaps is the USER's typo,
   exit 1. Gap twin: rc_means_stmt_gap.sas. expect-rc: 1 */
data h;
  input x;
  datalines;
1
;
run;
proc means data=h;
  var x;
  zzzq x;
run;

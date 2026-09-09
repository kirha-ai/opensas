/* GAP-gapsexitingone §5b re-verdict — `/ autonam` is not one of the six
   documented PROC MEANS OUTPUT options (AUTOLABEL/AUTONAME/KEEPLEN/LEVELS/
   NOINHERIT/WAYS), so it is the USER's typo, exit 1. Gap twin:
   rc_means_outopt_gap.sas. expect-rc: 1 */
data h;
  input x;
  datalines;
1
;
run;
proc means data=h;
  var x;
  output out=o n= / autonam;
run;

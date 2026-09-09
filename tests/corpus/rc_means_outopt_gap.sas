/* GAP-gapsexitingone §5b re-verdict — LEVELS is a documented PROC MEANS
   OUTPUT `/` option (OUTPUT statement dictionary, printed pp. 1503-1511)
   opensas does not implement — an opensas gap, exit 2. Typo twin:
   rc_means_outopt_typo.sas. expect-rc: 2 */
data h;
  input x;
  datalines;
1
;
run;
proc means data=h;
  var x;
  output out=o n= / levels;
run;

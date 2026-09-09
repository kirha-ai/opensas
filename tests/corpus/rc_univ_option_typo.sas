/* GAP-gapsexitingone §5b re-verdict — a TYPO'd PROC UNIVARIATE option
   (`nromal`) is the USER's error, exit 1. The option dictionary closes
   the set, so the catch-all can tell a typo from an unimplemented option;
   the gap twin pins NORMAL at rc 2. expect-rc: 1 */
data h;
  input x;
  datalines;
1
;
run;
proc univariate data=h nromal;
  var x;
run;

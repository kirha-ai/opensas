/* GAP-gapsexitingone §5b re-verdict — a TYPO'd PROC RANK option
   (`grups=4`) is the USER's error, exit 1. The option set is closed by
   the doc (printed pp. 2046-2048), so the catch-all can tell a typo from
   an unimplemented option; the gap twin pins PRESERVERAWBYVALUES at rc 2.
   expect-rc: 1 */
data h;
  input x;
  datalines;
1
;
run;
proc rank data=h out=r grups=4;
  var x;
run;

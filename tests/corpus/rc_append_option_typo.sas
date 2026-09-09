/* GAP-gapsexitingone §5b re-verdict — a TYPO'd PROC APPEND option
   (`froce`) is the USER's error, exit 1. The syntax diagram closes the
   option set at seven, so the catch-all can tell a typo from an
   unimplemented option; the gap twin pins NOWARN at rc 2. expect-rc: 1 */
data h;
  input x;
  datalines;
1
;
run;
proc append base=h data=h froce;
run;

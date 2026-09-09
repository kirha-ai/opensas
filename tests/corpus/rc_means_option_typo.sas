/* GAP-gapsexitingone §5b re-verdict — a TYPO'd PROC MEANS option
   (`maxddec=2`) is the USER's error, exit 1. The option set is closed by
   the doc (printed pp. 1482-1484), so the catch-all can tell a typo from
   an unimplemented option; the gap twin pins FW= at rc 2. expect-rc: 1 */
data h;
  input x;
  datalines;
1
;
run;
proc means data=h maxddec=2;
  var x;
run;

/* GAP-gapsexitingone §5b re-verdict — a TYPO'd PROC DELETE option (`dta=`)
   is the USER's error, exit 1. The PROC DELETE statement dictionary closes
   the option set, so the catch-all can tell a typo from an unimplemented
   option; the gap twin pins MEMTYPE= at rc 2. expect-rc: 1 */
data h;
  input x;
  datalines;
1
;
run;
proc delete data=h dta=h;
run;

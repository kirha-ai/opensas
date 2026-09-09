/* GAP-gapsexitingone §5b re-verdict — a TYPO'd PROC DATASETS option
   (`kll`) is the USER's error, exit 1. The Summary of Optional Arguments
   closes the option set, so the catch-all can tell a typo from an
   unimplemented option; the gap twin pins NOPRINT at rc 2. expect-rc: 1 */
data h;
  input x;
  datalines;
1
;
run;
proc datasets library=work kll nolist;
run;
quit;

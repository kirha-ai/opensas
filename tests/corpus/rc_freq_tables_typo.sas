/* GAP-gapsexitingone §5b re-verdict — a TYPO'd TABLES option (`chisqq`)
   is the USER's error, exit 1. Table 3.9 closes the TABLES option set, so
   the catch-all can tell a typo from an unimplemented option; the gap twin
   pins MISSPRINT at rc 2. expect-rc: 1 */
data h;
  input x;
  datalines;
1
;
run;
proc freq data=h;
  tables x / chisqq;
run;

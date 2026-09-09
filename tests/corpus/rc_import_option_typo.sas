/* GAP-gapsexitingone §5b re-verdict — a TYPO'd PROC IMPORT option
   (`dbm=csv`) is the USER's error, exit 1. The syntax block closes the
   statement option set, so the catch-all can tell a typo from an
   unimplemented option; the gap twin pins TABLE= at rc 2. expect-rc: 1 */
data h;
  input x;
  datalines;
1
;
run;
proc import datafile="/no/such.csv" out=b dbm=csv;
run;

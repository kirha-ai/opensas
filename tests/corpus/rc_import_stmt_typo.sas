/* GAP-gapsexitingone §5b re-verdict — a TYPO'd PROC IMPORT sub-statement
   (`getname=yes`) is the USER's error, exit 1. The delimited/JMP
   sub-statement list is closed by the doc (MIXED= included — it is from
   the PC Files book, not this one), so the catch-all can tell a typo
   from an unimplemented option; the gap twin pins VARNAMEROW= at rc 2.
   expect-rc: 1 */
data h;
  input x;
  datalines;
1
;
run;
proc import datafile="/no/such.csv" out=b dbms=csv;
  getname=yes;
run;

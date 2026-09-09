/* GAP-gapsexitingone §5b re-verdict — a TYPO'd PROC EXPORT sub-statement
   (`putname=no`) is the USER's error, exit 1. The delimited/JMP
   sub-statement list is closed by the doc, so the catch-all can tell a
   typo from an unimplemented option; the gap twin pins DELIMITER= at
   rc 2. expect-rc: 1 */
data h;
  input x;
  datalines;
1
;
run;
proc export data=h outfile="/tmp/rc_export_stypo.csv" dbms=csv;
  putname=no;
run;

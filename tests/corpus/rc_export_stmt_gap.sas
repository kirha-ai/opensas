/* GAP-gapsexitingone §5b re-verdict — DELIMITER= is a documented PROC
   EXPORT delimited-file sub-statement (printed p. 851) opensas does not
   implement — an opensas gap, exit 2. Typo twin:
   rc_export_stmt_typo.sas. expect-rc: 2 */
data h;
  input x;
  datalines;
1
;
run;
proc export data=h outfile="/tmp/rc_export_sgap.csv" dbms=csv;
  delimiter=',';
run;

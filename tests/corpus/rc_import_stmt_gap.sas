/* GAP-gapsexitingone §5b re-verdict — VARNAMEROW= is a documented PROC
   IMPORT delimited-file sub-statement (printed p. 1327) opensas does not
   implement — an opensas gap, exit 2. The guard fires before any file is
   read. Typo twin: rc_import_stmt_typo.sas. expect-rc: 2 */
data h;
  input x;
  datalines;
1
;
run;
proc import datafile="/no/such.csv" out=b dbms=csv;
  varnamerow=2;
run;

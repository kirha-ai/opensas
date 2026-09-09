/* GAP-gapsexitingone §5b re-verdict — TABLE= is a documented SAS 9.4 PROC
   IMPORT option (syntax block, Procedures Guide 7th ed. printed
   pp. 1327-1328) opensas does not implement — an opensas gap, exit 2.
   The guard fires before any file is read. Typo twin:
   rc_import_option_typo.sas. expect-rc: 2 */
data h;
  input x;
  datalines;
1
;
run;
proc import datafile="/no/such.csv" out=b dbms=csv table="t";
run;

/* GAP-gapsexitingone §5b re-verdict — LABEL is a documented SAS 9.4 PROC
   EXPORT option (syntax block, Procedures Guide 7th ed. printed
   pp. 851-852) opensas does not implement — an opensas gap, exit 2. Typo
   twin: rc_export_option_typo.sas. expect-rc: 2 */
data h;
  input x;
  datalines;
1
;
run;
proc export data=h outfile="/tmp/rc_export_gap.csv" dbms=csv label;
run;

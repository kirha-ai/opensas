/* GAP-gapsexitingone §5b re-verdict — MEMTYPE= is a documented SAS 9.4 PROC
   DELETE option (Procedures Guide, 7th ed., PROC DELETE Statement, printed
   pp. 786-787) opensas does not implement — an opensas gap, exit 2. Typo
   twin: rc_delete_option_typo.sas. expect-rc: 2 */
data h;
  input x;
  datalines;
1
;
run;
proc delete data=h memtype=catalog;
run;

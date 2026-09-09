/* GAP-gapsexitingone §5b re-verdict — MISSPRINT is a documented SAS 9.4
   TABLES option (Statistical Procedures Table 3.9, printed pp. 104-106)
   opensas does not implement — an opensas gap, exit 2. Typo twin:
   rc_freq_tables_typo.sas. expect-rc: 2 */
data h;
  input x;
  datalines;
1
;
run;
proc freq data=h;
  tables x / missprint;
run;

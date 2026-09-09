/* GAP-gapsexitingone §5b re-verdict — NOPRINT is a documented SAS 9.4 PROC
   DATASETS statement option (Summary of Optional Arguments, Procedures
   Guide 7th ed. printed pp. 578-579) opensas does not implement — an
   opensas gap, exit 2. Typo twin: rc_datasets_option_typo.sas.
   expect-rc: 2 */
data h;
  input x;
  datalines;
1
;
run;
proc datasets library=work noprint nolist;
run;
quit;

/* BUG-proctypoexits2 — a TYPO'd PROC COMPARE option (`criterionn=`) is the
   USER's error, exit 1 — the typo used to silently re-arm the default fuzz
   (BUG-comparesilentopts) and then exited 2, blaming opensas. The valid set
   is closed (Procedures Guide, 7th ed., printed pp. 428-435); the gap twin
   (rc_compare_option_gap.sas) pins OUTSTATS= at rc 2. expect-rc: 1 */
data h;
  input x;
  datalines;
1
;
run;
proc compare base=h compare=h criterionn=0.1;
run;

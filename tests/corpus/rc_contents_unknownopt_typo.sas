/* BUG-proctypoexits2 — a TYPO'd PROC CONTENTS option (`dta=`) is the USER's
   error, exit 1, not an opensas gap. The valid set is closed (Procedures
   Guide, 7th ed., printed pp. 493-497); the gap twin
   (rc_contents_option_gap.sas) pins DIRECTORY at rc 2. expect-rc: 1 */
data h;
  input x;
  datalines;
1
;
run;
proc contents data=h dta=h;
run;

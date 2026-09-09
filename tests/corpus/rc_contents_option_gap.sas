/* BUG-proctypoexits2 — the rc-2 twin: DIRECTORY is a documented SAS 9.4
   PROC CONTENTS option (Procedures Guide, 7th ed., printed pp. 493-497)
   opensas does not implement — an opensas gap, exit 2. Typo twin:
   rc_contents_unknownopt_typo.sas. expect-rc: 2 */
data h;
  input x;
  datalines;
1
;
run;
proc contents data=h directory;
run;

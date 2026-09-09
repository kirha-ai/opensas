/* BUG-proctypoexits2 — a TYPO'd PROC SORT option (`oout=`) is the USER's
   error, exit 1 ("fix your SAS"), not an opensas gap. The valid set is
   closed (Base SAS 9.4 Procedures Guide, 7th ed., printed pp. 2406-2408),
   so the catch-all can tell a typo from an unimplemented option; the gap
   twin (rc_sort_option_gap.sas) pins FORCE at rc 2. expect-rc: 1 */
data h;
  input x;
  datalines;
1
;
run;
proc sort data=h oout=h;
  by x;
run;

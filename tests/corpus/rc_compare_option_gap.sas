/* BUG-proctypoexits2 — the rc-2 twin: OUTSTATS= is a documented SAS 9.4
   PROC COMPARE option (Procedures Guide, 7th ed., printed pp. 428-435)
   opensas does not implement — an opensas gap, exit 2. Typo twin:
   rc_compare_unknownopt_typo.sas. expect-rc: 2 */
data h;
  input x;
  datalines;
1
;
run;
proc compare base=h compare=h outstats=s;
run;

/* BUG-proctypoexits2 — the rc-2 twin: INDB= is the one documented SAS 9.4
   PROC TRANSPOSE option (Procedures Guide, 7th ed., printed pp. 2697-2699)
   opensas does not implement — an opensas gap, exit 2. Typo twin:
   rc_transpose_unknownopt_typo.sas. expect-rc: 2 */
data h;
  input x;
  datalines;
1
;
run;
proc transpose data=h indb=no;
  var x;
run;

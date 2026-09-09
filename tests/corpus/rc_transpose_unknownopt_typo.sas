/* BUG-proctypoexits2 — a TYPO'd PROC TRANSPOSE option (`prefx=`) is the
   USER's error, exit 1. TRANSPOSE's documented option set (Procedures
   Guide, 7th ed., printed pp. 2697-2699) is fully implemented but INDB=,
   so any other unknown name is a typo. Gap twin: rc_transpose_option_gap.
   expect-rc: 1 */
data h;
  input x;
  datalines;
1
;
run;
proc transpose data=h prefx=c;
  var x;
run;

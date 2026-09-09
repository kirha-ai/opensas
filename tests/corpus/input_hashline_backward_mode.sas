/* BUG-backwardhashnrec: a BACKWARD `#n` line pointer under MISSOVER/TRUNCOVER
   released the LAST record visited (`last = rec` in the per-record segment
   branch, BUG-inputmultirecmode), not the HIGH-WATER mark the FLOWOVER path
   returns from readList (BUG-inputlinehighwater). 4 records produced 4
   observations (sliding window) plus a fabricated all-missing EOF row, while
   the identical FLOWOVER program gave the correct 2. One construct, three
   INFILE modes, one answer — pinned side by side so the two record-advance
   paths cannot silently disagree again. (no PHI) */
data fl;                                   /* default FLOWOVER */
  input #2 a 5. #1 b 5.;
datalines;
11111
22222
33333
44444
;
run;
proc print data=fl noobs; run;

data mo;
  infile datalines missover;
  input #2 a 5. #1 b 5.;
datalines;
11111
22222
33333
44444
;
run;
proc print data=mo noobs; run;

data tc;
  infile datalines truncover;
  input #2 a 5. #1 b 5.;
datalines;
11111
22222
33333
44444
;
run;
proc print data=tc noobs; run;

/* 3-record group, forward-then-backward (#1 #3 #2): high-water = #3 */
data m3;
  infile datalines truncover;
  input #1 a 5. #3 c 5. #2 b 5.;
datalines;
11111
22222
33333
44444
55555
66666
;
run;
proc print data=m3 noobs; run;

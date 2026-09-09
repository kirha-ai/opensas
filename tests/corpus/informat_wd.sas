/* BUG-inputfmtseq: formatted `w.d` INPUT reads fixed columns, not tokens.
   x = cols 1-5 "12345" → 123.45; y = cols 6-11 " 12345" → 12.345. */
data d;
  input x 5.2 y 6.3;
  datalines;
12345 123456
;
run;
proc print data=d noobs; run;

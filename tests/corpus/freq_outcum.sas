data have; input x; datalines;
1
2
2
3
;
run;
/* GAP-freqignoreopt: / outcum adds CUM_FREQ/CUM_PCT to a one-way OUT= dataset
   (used to be silently dropped). CUM_FREQ = running COUNT, CUM_PCT = running
   PERCENT over the sorted levels. */
proc freq data=have; tables x / out=fo outcum noprint; run;
proc print data=fo; run;

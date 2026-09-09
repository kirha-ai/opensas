/* QA tick155: pins BUG-univquant9010 (1b2ad13) decile rows (90%/10%) with the
   adversarial data the shipped fixtures lack — ties AND negatives, n=10.
   Def-5 (default): P90 avgs x9,x10 = (7+12)/2 = 9.5; P10 avgs x1,x2 = -5;
   P50 avgs x5,x6 = (0+3)/2 = 1.5. Guards the deciles + the surrounding
   quantile rows against re-pin drift. */
data tn; input x @@; datalines;
-5 -5 -2 0 0 3 3 3 7 12
;
run;
proc univariate data=tn; var x; run;

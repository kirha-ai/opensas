/* BUG-mergenobyinflag (regression lock): a MERGE with NO BY statement is a
   positional one-to-one join; in= flags reflect PER-SOURCE exhaustion — each
   flag is 1 while its own source still has a record and 0 once that source is
   spent, independently. Here a has 3 rows, b has 2: obs 3 carries fa=1 fb=0
   (b exhausted, y retained-then-not-reset per the SET-retain rule => y is the
   last b value . since b contributes nothing). Hand-verified vs SAS 9.4. */
data a; input x; datalines;
1
2
3
;
run;
data b; input y; datalines;
10
20
;
run;
data m;
  merge a(in=ina) b(in=inb);
  fa = ina; fb = inb;
run;
proc print data=m noobs; run;

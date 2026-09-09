/* GAP-sortlow-tick282 F6: THREADS/NOTHREADS/OVERWRITE/DATECOPY are accepted as
   benign no-ops (like TAGSORT/EQUALS) — none can change the sort RESULT. */
data d; input x; datalines;
3
1
2
;
run;
proc sort data=d threads;   by x; run;
proc sort data=d nothreads; by x; run;
proc sort data=d overwrite out=o1; by x; run;
proc sort data=d datecopy  out=o2; by x; run;
proc print data=d noobs; run;
proc print data=o1 noobs; run;
proc print data=o2 noobs; run;

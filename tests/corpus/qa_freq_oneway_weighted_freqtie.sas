/* GAP-freq-table-complete: signed weights preserve counts, suppress
   percentages, and ORDER=FREQ ties use ascending raw value (SAS oracle). */
data t;
  input c $ wt;
  datalines;
b 3
a 2
c 4
a 1
b 0
c -5
d 3
b 0
;
run;
/* Counts a=3,b=3,d=3,c=-1; zero observations excluded. */
proc freq data=t order=freq;
  tables c;
  weight wt;
run;

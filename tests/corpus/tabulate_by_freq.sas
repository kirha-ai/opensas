/* BUG-tabulatebyfreq: BY-group tables + FREQ weighting.
   Control (no by/freq) must stay byte-identical to a plain TABULATE. */
data have;
  input site trt $ sales;
  datalines;
1 A 100
1 B 200
2 A 300
2 A 400
2 B 500
;
run;

/* control: no BY / no FREQ — plain pooled table */
proc tabulate data=have;
  class trt;
  table trt, sales*sum;
run;

/* F1: BY site -> one table per site, values per group (not pooled) */
proc tabulate data=have;
  by site;
  class trt;
  table trt, sales*sum;
run;

/* F2: FREQ f -> each obs counts trunc(f) times; N=Sum(trunc(f)), sums weighted */
data counts;
  input trt $ sales f;
  datalines;
A 10 3
B 20 2
;
run;

proc tabulate data=counts;
  freq f;
  class trt;
  table trt, sales*(n sum);
run;

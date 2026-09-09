/* rbreakemptybody: RBREAK AFTER / SUMMARIZE on an EMPTY (WHERE-filtered to zero
   obs) report. SAS emits a header only — NOT a spurious grand-total line of
   missing values. Guards the empty-body skip on the grand-total append. */
data sales;
  input reg $ units revenue;
  datalines;
E 1 10
W 2 20
;
run;

proc report data=sales nowd;
  column reg units revenue;
  define reg / group;
  define units / analysis sum;
  define revenue / analysis sum;
  where units > 100;
  rbreak after / summarize;
run;

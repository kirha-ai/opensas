/* FEAT-procreport-2 break-summarize: BREAK AFTER <group var> / SUMMARIZE emits a
   subtotal (SUM of the analysis columns) after each group; RBREAK AFTER / SUMMARIZE
   emits a grand-total line after all rows. The break variable's value shows on the
   subtotal line; the grand total blanks it. Two group vars pins the nesting: the
   break is on the LEFT var (reg), so a subtotal covers all of its prod rows. */
data sales;
  input reg $ prod $ units revenue;
  datalines;
E A 1 10
E A 2 20
E B 3 30
W A 4 40
W B 5 50
;
run;

proc report data=sales nowd;
  column reg prod units revenue;
  define reg / group;
  define prod / group;
  define units / analysis sum;
  define revenue / analysis sum;
  break after reg / summarize;
  rbreak after / summarize;
run;

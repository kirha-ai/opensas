/* procreport rest3 break-before: BREAK BEFORE <group var> / SUMMARIZE emits a
   subtotal (SUM of the analysis columns) BEFORE each group's detail rows; RBREAK
   BEFORE / SUMMARIZE emits a grand-total line before all rows. The break variable's
   value shows on its subtotal line; the grand total blanks it. This mirrors the
   AFTER form (report_break_summarize) but with the summary placed first. */
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
  break before reg / summarize;
  rbreak before / summarize;
run;

/* procreport rest3 LINE (basic): a LINE statement inside a compute-after block
   writes a free-text summary line at the break position — literal text, a numeric
   variable value (optionally formatted), and @col column pointers. Here the group
   subtotal (compute after reg) prints a per-region total line, and the grand total
   (compute after / rbreak) prints an overall total. LINE reads the AGGREGATED
   values reportSummary binds, so `revenue`/`units` are the summed break values. */
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
  compute after reg;
    line @3 'region total units=' units ' revenue=' revenue;
  endcomp;
  compute after;
    line @3 'GRAND revenue ' revenue dollar10.2;
  endcomp;
run;

/* compute-at-break: a COMPUTED column filled ON each BREAK/RBREAK SUMMARIZE row
   by a `compute after` block, evaluated over that row's AGGREGATED (summed)
   values — pct = revenue / units. The break subtotal (reg) and the grand total
   (rbreak) each show pct computed from their own summed revenue/units; the GROUP
   detail rows leave pct blank (only compute-after drives it).
     E subtotal: units=5, revenue=25 -> pct=5
     W subtotal: units=5, revenue=45 -> pct=9
     grand:      units=10, revenue=70 -> pct=7  */
data sales;
  input reg $ prod $ units revenue;
  datalines;
E A 2 10
E A 1 5
E B 2 10
W A 3 27
W B 2 18
;
run;

proc report data=sales nowd;
  column reg prod units revenue pct;
  define reg / group;
  define prod / group;
  define units / analysis sum;
  define revenue / analysis sum;
  define pct / computed;
  break after reg / summarize;
  rbreak after / summarize;
  compute after reg;
    pct = revenue / units;
  endcomp;
  compute after;
    pct = revenue / units;
  endcomp;
run;

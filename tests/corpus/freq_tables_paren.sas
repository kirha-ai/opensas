data d;
  input a b c;
  datalines;
1 4 7
1 5 7
2 4 8
2 4 8
;
run;

/* BUG-freqtablesparen: a parenthesized variable group in TABLES expands —
   `tables (a b);` = `tables a b;` (two one-way tables), never silently
   dropped. */
proc freq data=d;
  tables (a b);
run;

/* The group distributes over a crossing: `(a b)*c` = `a*c b*c`. */
proc freq data=d;
  tables (a b)*c;
run;

/* Control: plain one-way and crosstab requests are unchanged. */
proc freq data=d;
  tables a;
  tables b*c;
run;

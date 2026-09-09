/* GAP-tableopt + GAP-reportusage (tick330 EBNF audit, Phase-G).
   TABLE_OPTION: one-way `/ list` is a DOCUMENTED no-op — the SAS 9.4 PROC FREQ
   TABLES-statement doc scopes LIST to "two-way to n-way tables" (a one-way
   table is list-form already). Proven BY CONSTRUCTION below: the / list table
   and the no-option table render byte-identically. n-way / list stays fail-
   loud (NOTE-freqlistfmt) — pinned by the captured test in src/proc.zig.
   REPORT_USAGE: every DEFINE usage is honoured — GROUP collapses to one row
   per level, ORDER sorts ascending on the underlying value and blanks repeats,
   DISPLAY shows as-is, ANALYSIS carries the stat word (SUM default). ACROSS
   stays fail-loud and its loud arm names it ("UNSUPPORTED: PROC REPORT
   ACROSS", probe-verified; captured test at src/proc.zig BUG-reportacross). */
data d;
  input g $ x;
  datalines;
b 1
a 2
b 3
a 4
;
run;
proc freq data=d;
  tables g / list;
run;
proc freq data=d;
  tables g;
run;
proc report data=d nowd;
  columns g x;
  define g / group;
  define x / analysis sum;
run;
proc report data=d nowd;
  columns g x;
  define g / order;
  define x / display;
run;

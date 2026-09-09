/* GAP-ebnfrcwrongclass (table_option LIST row): LIST is a DOCUMENTED PROC
   FREQ TABLES option — Table 3.9 (Base SAS 9.4 Procedures Guide: Statistical
   Procedures, printed p.105, === pdf 108 ===): "LIST Displays two-way to
   n-way tables in list format" — and real SAS runs `tables g*h / list;`
   clean. opensas only has the crosstab grid, so the render loop refuses LOUD
   rather than silently substitute the wrong layout (NOTE-freqlistfmt) — but
   it exited rc 1 "your SAS is broken". Refusing a documented option is OUR
   gap: NAMED rc 2 (D-009/D-009b(i)), message byte-identical. One-way / list
   stays the documented no-op (a one-way table is list form already), and
   `/ freq` stays the rc-1 typo class — Table 3.9 closes the TABLES option
   set and FREQ is not in it (pinned by the captured test in src/proc.zig).
   expect-rc: 2 */
data d;
  input g h;
  datalines;
1 7
2 7
2 8
3 8
;
run;
proc freq data=d;
  tables g*h / list;
run;

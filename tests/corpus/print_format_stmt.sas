/* BUG-printfmtstmt: a FORMAT statement inside PROC PRINT applies that format to
   the named column(s) when rendering (it was silently ignored, printing the raw
   value, before). Several var/format pairs share one statement (SAS shape:
   `format a fmt1. b fmt2.;`). The override is per-print — a later PROC PRINT
   without a FORMAT statement shows the raw values again. */
data w;
  x = 0.5;
  y = 1234.5;
  d = '15jan2024'd;
run;
proc print data=w;
  var x y d;
  format x percent8.1 y dollar9.2 d date9.;
run;
proc print data=w; run;

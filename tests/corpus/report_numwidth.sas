/* BUG-reportnumwidth (MED, silent-wrong): PROC REPORT added +2 to every numeric
   column width — including columns with an explicit FORMAT= — so a `format=dollar8.2`
   analysis column rendered 10-wide instead of 8. SAS (and PROC PRINT) render an
   explicit-format numeric column at exactly the format width; the 2-blank gutter
   between columns is separate. The two reports below print the same value through
   dollar8.2 and MUST be byte-identical in the "v" column width (8). */
data d;
  input v;
  datalines;
12.5
;
run;

proc report data=d nowd;
  column v;
  define v / analysis sum format=dollar8.2;
run;

proc print data=d noobs;
  var v;
  format v dollar8.2;
run;

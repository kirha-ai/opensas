/* GAP-printsplit: PROC PRINT split='*' breaks a column header label on '*'
   into multiple header lines (the '*' is consumed). A label without the
   split char sits on the bottom header line; no split= -> unchanged header. */
data d;
  age = 42;
  visit = 1;
  label age = "Age at*Visit 1";
run;
/* split header: age gets a 2-line header, visit (no '*') on the bottom line */
proc print data=d split='*' label; run;
/* control: no split= renders the raw label exactly as before */
proc print data=d noobs label; run;

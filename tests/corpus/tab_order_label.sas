/* GAP-tabulateopts: PROC TABULATE options that used to be SILENT no-ops are
   honored. ORDER=FREQ sorts the class levels by descending count (b:3, a:2,
   c:1 — not the lexical a,b,c); ORDER=DATA keeps first-appearance order
   (c,a,b). LABEL heads the row/analysis columns, KEYLABEL renames the Sum
   heading, and the TABLE `/ box='…'` text fills the corner box (a `/` option
   used to be mis-parsed into the bogus "analysis variable not found"). */
data d;
  input g $ v;
  datalines;
c 10
a 20
b 30
b 40
a 50
b 60
;
run;
proc tabulate data=d order=freq;
  class g;
  var v;
  table g, v*sum / box='Grp';
  label g='Group' v='Dose';
  keylabel sum='Total';
run;
proc tabulate data=d order=data;
  class g;
  var v;
  table g, v*n;
run;

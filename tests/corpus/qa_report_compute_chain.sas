/* QA tick194: PROC REPORT COMPUTE increment-1 (608c406) — VERIFIED GREEN.
   Multiple computed columns in the detail path, with a computed column
   (dbl) referencing another computed column (tot) that precedes it in the
   COLUMN list. Compute blocks written in column order; SAS evaluates left to
   right so tot=a+b then dbl=tot*2. Pins the chained-computed-ref feature that
   report_compute.sas (single computed col) does not cover, and guards the
   idxs->src output-column model change against a chained-ref regression. */
data d; input a b; datalines;
1 10
2 20
3 30
;
run;
proc report data=d nowd;
  column a b tot dbl;
  define a / display;
  define b / display;
  define tot / computed;
  define dbl / computed;
  compute tot; tot = a + b; endcomp;
  compute dbl; dbl = tot * 2; endcomp;
run;

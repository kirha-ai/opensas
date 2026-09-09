data have; input g $ x; datalines;
A 1
A 2
A 4
B 10
;
run;
/* BUG-tabrawfloat: a non-integer TABULATE cell used to print the raw 17-digit
   f64 (2.3333333333333335). SAS's default cell format is BEST12. → 2.3333333333,
   the same path PROC PRINT/MEANS use. Integer cells unchanged. */
proc tabulate data=have; class g; var x; table g, x*mean; run;
/* GAP-tabformat: proc-level FORMAT= is the default cell format … */
proc tabulate data=have format=8.2; class g; var x; table g, x*mean; run;
/* … and a crossing's *f= overrides it (was silently ignored / derailed the
   analysis-var scan). */
proc tabulate data=have; class g; var x; table g, x*mean*f=6.2; run;

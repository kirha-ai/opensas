/* BUG-tabulatezerocrash: a 2-way cross (CLASS var in the column dim) over a
   dataset filtered to 0 observations used to PANIC — the width math underflowed
   `ndata - 1` on a usize when there were no column levels (SIGABRT, rc134).
   With no column levels there is no table to draw, so the cross renders nothing
   (mirroring PROC FREQ's empty-input no-op) and execution continues. A column
   ALL margin keeps a grand-total column, so that 0-obs cross still renders. */
data d; input r $ c $ v; datalines;
x p 1
y q 2
;
run;

/* where= filters to 0 rows -> previously crashed, now renders nothing */
proc tabulate data=d(where=(v>99)); class r c; table r, c*v*sum; run;

/* column ALL margin over 0 rows: a grand-total column still renders (sum=.) */
proc tabulate data=d(where=(v>99)); class r c; var v; table r all, c*v*sum all*v*sum; run;

/* proof the step above did not abort the run */
data _null_; put "survived 0-obs tabulate cross"; run;

/* a normal (non-empty) 2-way cross is unaffected */
proc tabulate data=d; class r c; var v; table r, c*v*sum; run;

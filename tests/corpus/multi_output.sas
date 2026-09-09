/* BUG-multioutput: `data a b;` creates BOTH outputs (SAS 9.4 Language Reference: Concepts, DATA
   statement: multiple output datasets; the implicit bottom-of-step output and
   a bare `output;` write the current observation to EVERY named dataset; ALL
   named datasets are created even at 0 observations). Covers: two outputs,
   three outputs, 0-obs creation, bare-output fan-out, per-output options. */
data src;
  input a b;
  datalines;
1 10
2 20
3 30
;
run;

data m1 m2;
  set src;
run;
proc print data=m1; run;
proc print data=m2; run;

data t1 t2 t3;
  set src;
run;
proc print data=t3; run;

data e1 e2;
  set src;
  if a > 99;
run;
proc print data=e2; run;

data f1 f2;
  set src;
  output;
run;
proc print data=f2; run;

data outa(keep=a) outb(keep=b where=(b>15));
  set src;
run;
proc print data=outa; run;
proc print data=outb; run;

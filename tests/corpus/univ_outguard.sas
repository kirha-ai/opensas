/* GAP-meansoutguards (b): PROC UNIVARIATE OUTPUT OUT= with an unimplemented option
   (pctlpts=/pctlpre=) must fail LOUD (ERROR, non-zero exit, run halts) — never skip
   the option and silently drop the requested P33/P66 percentile variables. The PROC
   PRINT below is a regression tripwire: if the guard is removed, `o` is built with
   only `med` and leaks to stdout, failing this fixture.
   Correct (guarded) behavior: the run stops at the UNIVARIATE error, stdout empty.
   expect-rc: 2 */
data d;
  do g = 1 to 2;
    x = g;
    output;
  end;
run;
proc univariate data=d;
  var x;
  output out=o pctlpts=33 66 pctlpre=P median=med;
run;
proc print data=o noobs;
run;

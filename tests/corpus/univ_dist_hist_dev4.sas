/* FEAT-univ-distributions: numerical HISTOGRAM output under PROC NOPRINT. */
options nodate nonumber;
data d;
input g x f;
datalines;
1 1 2
1 2 1
1 4 1
1 8 1
2 2 1
2 3 1
2 6 1
2 9 1
;
proc univariate data=d noprint;
by g;freq f;var x;
histogram x / noplot normal(mu=0 sigma=2 noprint)
 endpoints=0 to 10 by 2 outhistogram=h;
histogram x / noplot endpoints=0 to 10 by 2 rtinclude outhistogram=r;
run;
data _null_;set h(in=fitted) r;file print;
if fitted then put g 1. ' ' _MINPT_ 2. ' ' _COUNT_ 1. ' ' _OBSPCT_ 6.2 ' ' _EXPPCT_ 10.6;
else put g 1. ' ' _MAXPT_ 2. ' ' _COUNT_ 1. ' ' _OBSPCT_ 6.2;
run;

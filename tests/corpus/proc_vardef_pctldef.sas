/* BUG-statvardef + BUG-univpctldef: VARDEF= and PCTLDEF= are honored.
   x = 2 4 6 8 10 → mean 6, CSS 40.
   VARDEF=N: Var=40/5=8, Std=2.8284271, CV=47.1404521, StdErr=2.8284271/√5=1.2649111.
   VARDEF=DF (default): Var=40/4=10, Std=3.1622777. */
data d; input x @@; datalines;
2 4 6 8 10
;
run;
proc means data=d vardef=n n mean var std cv stderr;
    var x;
run;
proc means data=d var std;
    var x;
run;
proc univariate data=d vardef=n;
    var x;
run;
proc univariate data=d;
    var x;
run;

/* PCTLDEF on y = 1..10 (SAS 9.4 UNIVARIATE "Calculating Percentiles"):
   def 1: Q1=2.5  Q3=7.5   (interp at n·t)        def 2: Q1=2 Q3=8 (ties→even)
   def 4: Q1=2.75 Q3=8.25  (interp at (n+1)·t)    def 5: Q1=3 Q3=8 (default) */
data d2; input y @@; datalines;
1 2 3 4 5 6 7 8 9 10
;
run;
proc univariate data=d2 pctldef=1;
    var y;
run;
proc univariate data=d2 pctldef=2;
    var y;
run;
proc univariate data=d2 pctldef=4;
    var y;
run;
proc univariate data=d2;
    var y;
run;

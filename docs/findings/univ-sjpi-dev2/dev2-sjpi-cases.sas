ods graphics off;
data d; input x @@; datalines;
1 2 3 4 6 8 10 15
;
proc univariate data=d noprint; var x; output out=stats n=n std=sd qrange=q; histogram x / noplot kernel(c=sjpi) outkernel=k; run;
data _null_; set stats; file print; put "CASE 0 " n=best32. sd=best32. q=best32.; run;
data _null_; set k(obs=1); file print; put "CASE 0 " _c_=best32.; run;
data d; input x @@; datalines;
1 2 3 4 5 6 7 8
;
proc univariate data=d noprint; var x; output out=stats n=n std=sd qrange=q; histogram x / noplot kernel(c=sjpi) outkernel=k; run;
data _null_; set stats; file print; put "CASE 1 " n=best32. sd=best32. q=best32.; run;
data _null_; set k(obs=1); file print; put "CASE 1 " _c_=best32.; run;
data d; input x @@; datalines;
0 1
;
proc univariate data=d noprint; var x; output out=stats n=n std=sd qrange=q; histogram x / noplot kernel(c=sjpi) outkernel=k; run;
data _null_; set stats; file print; put "CASE 2 " n=best32. sd=best32. q=best32.; run;
data _null_; set k(obs=1); file print; put "CASE 2 " _c_=best32.; run;
data d; input x @@; datalines;
0 1 2
;
proc univariate data=d noprint; var x; output out=stats n=n std=sd qrange=q; histogram x / noplot kernel(c=sjpi) outkernel=k; run;
data _null_; set stats; file print; put "CASE 3 " n=best32. sd=best32. q=best32.; run;
data _null_; set k(obs=1); file print; put "CASE 3 " _c_=best32.; run;
data d; input x @@; datalines;
0 1 2 3
;
proc univariate data=d noprint; var x; output out=stats n=n std=sd qrange=q; histogram x / noplot kernel(c=sjpi) outkernel=k; run;
data _null_; set stats; file print; put "CASE 4 " n=best32. sd=best32. q=best32.; run;
data _null_; set k(obs=1); file print; put "CASE 4 " _c_=best32.; run;
data d; input x @@; datalines;
0 0 1 1 2 2 3 3
;
proc univariate data=d noprint; var x; output out=stats n=n std=sd qrange=q; histogram x / noplot kernel(c=sjpi) outkernel=k; run;
data _null_; set stats; file print; put "CASE 5 " n=best32. sd=best32. q=best32.; run;
data _null_; set k(obs=1); file print; put "CASE 5 " _c_=best32.; run;
data d; input x @@; datalines;
0 0 0 0 0 0 0 1
;
proc univariate data=d noprint; var x; output out=stats n=n std=sd qrange=q; histogram x / noplot kernel(c=sjpi) outkernel=k; run;
data _null_; set stats; file print; put "CASE 6 " n=best32. sd=best32. q=best32.; run;
data _null_; set k(obs=1); file print; put "CASE 6 " _c_=best32.; run;
data d; input x @@; datalines;
1 1 1 1 1 1 1 1
;
proc univariate data=d noprint; var x; output out=stats n=n std=sd qrange=q; histogram x / noplot kernel(c=sjpi) outkernel=k; run;
data _null_; set stats; file print; put "CASE 7 " n=best32. sd=best32. q=best32.; run;
data _null_; set k(obs=1); file print; put "CASE 7 " _c_=best32.; run;
data d; input x @@; datalines;
1
;
proc univariate data=d noprint; var x; output out=stats n=n std=sd qrange=q; histogram x / noplot kernel(c=sjpi) outkernel=k; run;
data _null_; set stats; file print; put "CASE 8 " n=best32. sd=best32. q=best32.; run;
data _null_; set k(obs=1); file print; put "CASE 8 " _c_=best32.; run;
data d; input x @@; datalines;
0 1 2 3 4 5 6 100
;
proc univariate data=d noprint; var x; output out=stats n=n std=sd qrange=q; histogram x / noplot kernel(c=sjpi) outkernel=k; run;
data _null_; set stats; file print; put "CASE 9 " n=best32. sd=best32. q=best32.; run;
data _null_; set k(obs=1); file print; put "CASE 9 " _c_=best32.; run;
data d; input x @@; datalines;
1 2 3 4 6 8 10 150
;
proc univariate data=d noprint; var x; output out=stats n=n std=sd qrange=q; histogram x / noplot kernel(c=sjpi) outkernel=k; run;
data _null_; set stats; file print; put "CASE 10 " n=best32. sd=best32. q=best32.; run;
data _null_; set k(obs=1); file print; put "CASE 10 " _c_=best32.; run;
data d; input x @@; datalines;
-8 -3 -2 -1 0 1 2 3 8
;
proc univariate data=d noprint; var x; output out=stats n=n std=sd qrange=q; histogram x / noplot kernel(c=sjpi) outkernel=k; run;
data _null_; set stats; file print; put "CASE 11 " n=best32. sd=best32. q=best32.; run;
data _null_; set k(obs=1); file print; put "CASE 11 " _c_=best32.; run;
data d; input x @@; datalines;
0.1 0.2 0.25 0.4 0.6 1 2 5 12 30
;
proc univariate data=d noprint; var x; output out=stats n=n std=sd qrange=q; histogram x / noplot kernel(c=sjpi) outkernel=k; run;
data _null_; set stats; file print; put "CASE 12 " n=best32. sd=best32. q=best32.; run;
data _null_; set k(obs=1); file print; put "CASE 12 " _c_=best32.; run;
data d; input x @@; datalines;
20 23 26 29 35 41 47 62
;
proc univariate data=d noprint; var x; output out=stats n=n std=sd qrange=q; histogram x / noplot kernel(c=sjpi) outkernel=k; run;
data _null_; set stats; file print; put "CASE 13 " n=best32. sd=best32. q=best32.; run;
data _null_; set k(obs=1); file print; put "CASE 13 " _c_=best32.; run;
data d; input x @@; datalines;
-1 -2 -3 -4 -6 -8 -10 -15
;
proc univariate data=d noprint; var x; output out=stats n=n std=sd qrange=q; histogram x / noplot kernel(c=sjpi) outkernel=k; run;
data _null_; set stats; file print; put "CASE 14 " n=best32. sd=best32. q=best32.; run;
data _null_; set k(obs=1); file print; put "CASE 14 " _c_=best32.; run;
data d; input x @@; datalines;
0.001 0.002 0.003 0.004 0.006 0.008 0.01 0.015
;
proc univariate data=d noprint; var x; output out=stats n=n std=sd qrange=q; histogram x / noplot kernel(c=sjpi) outkernel=k; run;
data _null_; set stats; file print; put "CASE 15 " n=best32. sd=best32. q=best32.; run;
data _null_; set k(obs=1); file print; put "CASE 15 " _c_=best32.; run;
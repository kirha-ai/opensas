ods graphics off;
data d; input x @@; datalines;
0 0.1 0.2 0.5 1 2 8 100 1000 10000
;
proc univariate data=d noprint; histogram x / noplot kernel(k=n q t) outkernel=k;run;
data _null_;set k;by _type_ notsorted; file print;if first._type_ then put _all_;run;

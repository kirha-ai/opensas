ods graphics off;
data d;input x @@;datalines;
1 2 3 4 6 8 10 15
;
proc univariate data=d noprint;histogram x / noplot kernel(k=n q t c=sjpi) outkernel=k;run;
data _null_;set k;by _type_ notsorted;file print;if first._type_ then put _all_;run;

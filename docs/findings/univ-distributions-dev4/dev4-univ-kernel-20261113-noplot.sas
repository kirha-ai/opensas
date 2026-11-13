ods graphics off;
data d; input x @@; datalines;
1 2 3 4 6 8 10 15
;
proc univariate data=d noprint; histogram x / noplot kernel(k=n q t c=0.5) endpoints=0 to 20 by 5 outkernel=k;run;
data _null_;set k;file print;if _n_<=8 or mod(_n_,100)=0 then put _all_;run;
proc univariate data=d noprint; histogram x / noplot kernel(k=n q t) endpoints=0 to 20 by 5 outkernel=k;run;
data _null_;set k;file print;if _n_<=2 or mod(_n_,100)=0 then put _all_;run;

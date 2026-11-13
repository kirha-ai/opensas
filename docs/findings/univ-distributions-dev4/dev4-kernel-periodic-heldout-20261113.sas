ods graphics off;
data d;input x @@;datalines;
0 .3 .8 1
;
proc univariate data=d noprint;histogram x / noplot kernel(c=.2 .5 1 2) endpoints=-2 to 3 by .5 outkernel=k;run;
data _null_;set k;file print;if _value_=-.5 or _value_=.5 then put _c_=best32. _value_=best32. _density_=best32.;run;

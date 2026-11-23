data d;input z w f;u=2**(-400);x=z*u;datalines;
1 1 1
-3 .25 1
5 1.5 2
6 2 1
10 .75 3
;
run;
proc univariate data=d noprint vardef=df;var x;output out=t skewness=sk kurtosis=ku;run;data _null_;set t;file print;put 'SHAPE ' sk best32. ' ' ku best32.;run;

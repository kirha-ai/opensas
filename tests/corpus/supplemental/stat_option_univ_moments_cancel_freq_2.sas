data d;input x f;datalines;
4503599627370496 1
-4503599627370496 1
100000 2
;
run;proc univariate data=d noprint;var x;freq f;output out=t sum=s mean=m;run;data _null_;set t;file print;put 'RESIDUAL ' s best32. ' ' m best32.;run;

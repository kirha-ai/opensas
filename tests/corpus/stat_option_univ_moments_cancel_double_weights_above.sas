data d;input z w;u=2**(-12);x=z*u;datalines;
4503599627370496 2
-4503599627370496 2
223607 1
;
run;proc univariate data=d noprint idout;var x;id u;weight w;output out=t sum=s mean=m;run;data _null_;set t;su=s/u;mu=m/u;file print;put 'RESIDUAL ' su best32. ' ' mu best32.;run;

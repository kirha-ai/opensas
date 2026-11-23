data d;input z w f;offset=-7*2**38;u=2**(-12);x=offset+z*u;datalines;
0 2 1
2000 1 2
4000 .5 1
-1000 3 1
0 0 3
;
run;
proc univariate data=d noprint idout vardef=df;var x;id offset u;weight w;output out=t n=n mean=m css=css std=sd min=low max=high skewness=sk kurtosis=ku;run;data _null_;set t;dm=(m-offset)/u;second=sd/u;third=css/u/u;file print;put 'MOMENT ' n best32. ' ' dm best32. ' ' third best32. ' ' second best32. ' ' sk best32. ' ' ku best32.;run;

data d;input z w f;offset=4*2**38;u=2**(-12);x=offset+z*u;datalines;
0 1 1
0 .25 2
0 3 1
999 2 1
;
run;
proc univariate data=d noprint idout vardef=wdf;var x;id offset u;weight w;output out=t n=n mean=m css=css std=sd min=low max=high skewness=sk kurtosis=ku;run;data _null_;set t;dm=(m-offset)/u;second=sd/u;third=css/u/u;file print;put 'MOMENT ' n best32. ' ' dm best32. ' ' third best32. ' ' second best32. ' ' sk best32. ' ' ku best32.;run;

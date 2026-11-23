data d;input z w f;u=1;offset=2**44;x=offset+z;datalines;
0 1 2
1 .25 1
2 2 1
4 3 1
5 0 3
7 . 4
11 1.5 1
11 4 2
20 2 1
;
run;
proc univariate data=d noprint idout vardef=df;var x;id offset u;freq f;output out=t n=n mean=m css=css std=sd min=low max=high skewness=sk kurtosis=ku;run;data _null_;set t;dm=(m-offset)/u;second=high-low;third=css;file print;put 'MOMENT ' n best32. ' ' dm best32. ' ' third best32. ' ' second best32. ' ' sk best32. ' ' ku best32.;run;

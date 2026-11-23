data d;input z w f;u=2**(300);x=z*u;datalines;
1 1 1
-3 .25 1
5 1.5 2
6 2 1
10 .75 3
;
run;
ods output Moments=mo;proc univariate data=d  vardef=n;var x;output out=t skewness=sk kurtosis=ku;run;data _null_;set t;file print;put 'SHAPE ' sk best32. ' ' ku best32.;run;data _null_;set mo;if label1='Skewness' then do;file print;put 'ODS_SHAPE ' nValue1 best32. ' ' nValue2 best32.;end;run;

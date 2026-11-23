data d;input z w f;u=2**(-511);x=z*1*u;datalines;
-1 1 1
-1 1 1
0 1 1
1 1 1
1 1 1
;
run;proc univariate data=d noprint idout vardef=n;var x;id u;output out=q std=d uss=us css=cs;run;data _null_;set q;nd=d/u;nu=us/u/u;nc=cs/u/u;file print;put 'SQUARE ' nd best32. ' ' nu best32. ' ' nc best32.;run;

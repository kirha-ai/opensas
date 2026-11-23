data d;input z w f;u=2**(-511);x=z*0.99*u;datalines;
-2 .5 1
-.5 1 2
0 1 1
1 2 1
1 4 2
;
run;proc univariate data=d noprint idout vardef=df;var x;id u;freq f;output out=q std=d uss=us css=cs;run;data _null_;set q;nd=d/u;nu=us/u/u;nc=cs/u/u;file print;put 'SQUARE ' nd best32. ' ' nu best32. ' ' nc best32.;run;

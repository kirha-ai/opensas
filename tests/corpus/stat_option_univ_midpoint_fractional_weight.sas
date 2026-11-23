data d;input z w;x=z*1e308;datalines;
.8 .25
1.05 .25
;
run;proc univariate data=d noprint;var x;weight w;output out=q q1=a median=b q3=c;run;data _null_;set q;qa=a/1e308;qb=b/1e308;qc=c/1e308;file print;put 'MID ' qa best24. ' ' qb best24. ' ' qc best24.;run;

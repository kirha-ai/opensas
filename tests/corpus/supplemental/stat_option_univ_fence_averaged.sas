options nosyntaxcheck;data d;input z w f;x=z*1e308;datalines;
0 1 1
0 1 1
0 1 1
0 1 1
0 1 1
0 1 1
1 1 1
1 1 1
;
run;proc univariate data=d noprint pctldef=5;var x;output out=q n=n q1=a q3=b;run;data _null_;set q;lo=a/1e308;hi=b/1e308;file print;put 'FENCE ' n 3. ' ' lo best24. ' ' hi best24.;run;

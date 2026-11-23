/* expect-rc: 1 */
options nosyntaxcheck;data d;input z w f;x=z*1e308;datalines;
-1.4 1 1
-.8 1 1
;
run;proc univariate data=d noprint ;var x;output out=q n=n q1=a q3=b;run;data _null_;set q;lo=a/1e308;hi=b/1e308;file print;put 'FENCE ' n 3. ' ' lo best24. ' ' hi best24.;run;

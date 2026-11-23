/* expect-rc: 1 */
options syntaxcheck;data d;input x n;datalines;
1 3
2 7
;
run;
proc freq data=d;weight n;tables x/binomial(equiv p=.2 margin=.2);run;data after;z=7;run;data _null_;set after;file print;put 'NEXT ' z 1.;run;

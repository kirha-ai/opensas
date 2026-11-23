/* expect-rc: 1 */
options nosyntaxcheck;data d;input g c x y;datalines;
1 1 1 1
1 2 2 2
2 1 3 3
2 1 4 4
2 2 0 1
2 2 1e308 2
;
run;proc univariate data=d outtable=t;by g;class c;var x y;output out=q n=nx ny;run;data _null_;set t;file print;put 'CELL ' _var_ $1. ' ' c 1.;run;data _null_;set q;file print;put 'OUTPUT ' c 1.;run;

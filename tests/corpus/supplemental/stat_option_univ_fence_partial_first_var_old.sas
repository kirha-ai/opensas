/* expect-rc: 1 */
options nosyntaxcheck;data q t;sentinel=99;run;data d;input g c x y;datalines;
1 1 1 0
1 1 2 3
1 2 0 0
1 2 1e308 2
;
run;proc univariate data=d outtable=t;class c;var x y;output out=q n=nx ny;run;data _null_;set q;file print;put 'SAVED_q ' sentinel 2.;run;data _null_;set t;file print;put 'SAVED_t ' sentinel 2.;run;

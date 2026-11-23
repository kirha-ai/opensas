/* expect-rc: 1 */
options nosyntaxcheck;data d;input x y w;datalines;
1e155 . 1e200
;
run;proc univariate data=d noprint;var x y;weight w;output out=q n=n;run;data _null_;set q;file print;put 'COUNT ' n 1.;run;

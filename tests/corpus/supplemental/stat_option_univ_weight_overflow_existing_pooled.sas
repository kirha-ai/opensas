/* expect-rc: 1 */
options nosyntaxcheck;data q;g=9;n=99;m=42;run;data d;input g x y u f;w=u*2**511;datalines;
1 0 1 1 4
;
run;proc univariate data=d noprint;var x;weight w;freq f;output out=q n=n mean=m;run;data _null_;set q;file print;put 'WEIGHT ' n best32. ' ' m best32.;run;data _null_;set q;file print;put 'OLD ' n 2. ' ' m 2.;run;

data d;input a b y;datalines;
.A .Z 1
.A 1 2
1 .Z 4
1 2 8
._ ._ 16
1 1 32
;
run;
proc univariate data=d noprint;class a(missing order=internal order=data) b(missing);var y;output out=o sum=s;run;data _null_;set o;file print;put 'GROUP ' s 5.;run;

data _null_; file print; put 'Case univ_class_scope_both'; run;
data d;input a b y;datalines;
.A .Z 1
.A 1 2
1 .Z 4
1 2 8
._ ._ 16
1 1 32
;
run;
proc univariate data=d noprint;class a(missing) b(missing);var y;output out=o sum=s;run;data _null_;set o;file print;put 'GROUP ' s 5.;run;

data _null_; file print; put 'Case univ_class_scope_first'; run;
data d;input a b y;datalines;
.A .Z 1
.A 1 2
1 .Z 4
1 2 8
._ ._ 16
1 1 32
;
run;
proc univariate data=d noprint;class a(missing) b;var y;output out=o sum=s;run;data _null_;set o;file print;put 'GROUP ' s 5.;run;

data _null_; file print; put 'Case univ_class_scope_neither'; run;
data d;input a b y;datalines;
.A .Z 1
.A 1 2
1 .Z 4
1 2 8
._ ._ 16
1 1 32
;
run;
proc univariate data=d noprint;class a b;var y;output out=o sum=s;run;data _null_;set o;file print;put 'GROUP ' s 5.;run;

data _null_; file print; put 'Case univ_class_scope_second'; run;
data d;input a b y;datalines;
.A .Z 1
.A 1 2
1 .Z 4
1 2 8
._ ._ 16
1 1 32
;
run;
proc univariate data=d noprint;class a b(missing);var y;output out=o sum=s;run;data _null_;set o;file print;put 'GROUP ' s 5.;run;

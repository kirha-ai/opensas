data _null_; file print; put 'Case univ_class_special_plain_missing_formatted'; run;
data control;length fmtname $8 label $12;
input start label $;end=start;fmtname='Key';datalines;
. Zed
.A Join
1 Join
.Z Alpha
._ Underscore
2 Between
;
run;proc format cntlin=control;run;data d;input x y;datalines;
2 1
.A 2
1 4
. 8
.Z 16
._ 32
1 64
;
run;
proc univariate data=d noprint;class x(order=formatted missing);var y;output out=o n=n sum=s;run;data _null_;set o;file print;put 'GROUP ' n 3. s 6.;run;

data _null_; file print; put 'Case univ_class_special_plain_missing_freq'; run;
data control;length fmtname $8 label $12;
input start label $;end=start;fmtname='Key';datalines;
. Zed
.A Join
1 Join
.Z Alpha
._ Underscore
2 Between
;
run;proc format cntlin=control;run;data d;input x y;datalines;
2 1
.A 2
1 4
. 8
.Z 16
._ 32
1 64
;
run;
proc univariate data=d noprint;class x(order=freq missing);var y;output out=o n=n sum=s;run;data _null_;set o;file print;put 'GROUP ' n 3. s 6.;run;

data _null_; file print; put 'Case univ_class_special_plain_missing_internal'; run;
data control;length fmtname $8 label $12;
input start label $;end=start;fmtname='Key';datalines;
. Zed
.A Join
1 Join
.Z Alpha
._ Underscore
2 Between
;
run;proc format cntlin=control;run;data d;input x y;datalines;
2 1
.A 2
1 4
. 8
.Z 16
._ 32
1 64
;
run;
proc univariate data=d noprint;class x(order=internal missing);var y;output out=o n=n sum=s;run;data _null_;set o;file print;put 'GROUP ' n 3. s 6.;run;

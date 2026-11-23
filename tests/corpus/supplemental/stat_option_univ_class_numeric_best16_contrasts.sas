data _null_; file print; put 'Case univ_class_numeric_best16_data'; run;
data d;input x y;datalines;
-2 1
12 2
.75 4
-10.5 8
2 16
. 32
-2.25 64
10 128
0 256
.123456789012355 512
.123456789045678 1024
.123456789012345 2048
;
run;
proc format;value ord -2,-2.25='zneg' -10.5='yneg' .75='cfrac' 0='d0'
2='xpos' 10='bpos' 12='apos' .12-.13='group';run;
proc univariate data=d noprint;class x(order=data missing);format x best16.;var y;output out=o n=n sum=s;run;data _null_;set o;file print;put 'GROUP ' n 3. s 6.;run;

data _null_; file print; put 'Case univ_class_numeric_best16_formatted'; run;
data d;input x y;datalines;
-2 1
12 2
.75 4
-10.5 8
2 16
. 32
-2.25 64
10 128
0 256
.123456789012355 512
.123456789045678 1024
.123456789012345 2048
;
run;
proc format;value ord -2,-2.25='zneg' -10.5='yneg' .75='cfrac' 0='d0'
2='xpos' 10='bpos' 12='apos' .12-.13='group';run;
proc univariate data=d noprint;class x(order=formatted missing);format x best16.;var y;output out=o n=n sum=s;run;data _null_;set o;file print;put 'GROUP ' n 3. s 6.;run;

data _null_; file print; put 'Case univ_class_numeric_best16_freq'; run;
data d;input x y;datalines;
-2 1
12 2
.75 4
-10.5 8
2 16
. 32
-2.25 64
10 128
0 256
.123456789012355 512
.123456789045678 1024
.123456789012345 2048
;
run;
proc format;value ord -2,-2.25='zneg' -10.5='yneg' .75='cfrac' 0='d0'
2='xpos' 10='bpos' 12='apos' .12-.13='group';run;
proc univariate data=d noprint;class x(order=freq missing);format x best16.;var y;output out=o n=n sum=s;run;data _null_;set o;file print;put 'GROUP ' n 3. s 6.;run;

data _null_; file print; put 'Case univ_class_numeric_best16_internal'; run;
data d;input x y;datalines;
-2 1
12 2
.75 4
-10.5 8
2 16
. 32
-2.25 64
10 128
0 256
.123456789012355 512
.123456789045678 1024
.123456789012345 2048
;
run;
proc format;value ord -2,-2.25='zneg' -10.5='yneg' .75='cfrac' 0='d0'
2='xpos' 10='bpos' 12='apos' .12-.13='group';run;
proc univariate data=d noprint;class x(order=internal missing);format x best16.;var y;output out=o n=n sum=s;run;data _null_;set o;file print;put 'GROUP ' n 3. s 6.;run;

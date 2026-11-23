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
ods select Moments;proc univariate data=d;class x(order=internal missing);format x best12.;var y;run;

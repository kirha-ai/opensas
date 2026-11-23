data _null_; file print; put 'Case freq_level_order_custom_data'; run;
data d;input x w;datalines;
-2 1
12 1
.75 1
-10.5 1
2 1
. 1
-2.25 1
10 1
0 1
;
run;
proc format;value ord -2,-2.25='zneg' -10.5='yneg' .75='cfrac' 0='d0' 2='xpos' 10='bpos' 12='apos';run;
proc freq data=d order=data;format x ord.;weight w;tables x / missing out=o;run;data _null_;set o;file print;put 'LEVEL ' x 12.4;run;

data _null_; file print; put 'Case freq_level_order_custom_formatted'; run;
data d;input x w;datalines;
-2 1
12 1
.75 1
-10.5 1
2 1
. 1
-2.25 1
10 1
0 1
;
run;
proc format;value ord -2,-2.25='zneg' -10.5='yneg' .75='cfrac' 0='d0' 2='xpos' 10='bpos' 12='apos';run;
proc freq data=d order=formatted;format x ord.;weight w;tables x / missing out=o;run;data _null_;set o;file print;put 'LEVEL ' x 12.4;run;

data _null_; file print; put 'Case freq_level_order_custom_freq'; run;
data d;input x w;datalines;
-2 1
12 1
.75 1
-10.5 1
2 1
. 1
-2.25 1
10 1
0 1
;
run;
proc format;value ord -2,-2.25='zneg' -10.5='yneg' .75='cfrac' 0='d0' 2='xpos' 10='bpos' 12='apos';run;
proc freq data=d order=freq;format x ord.;weight w;tables x / missing out=o;run;data _null_;set o;file print;put 'LEVEL ' x 12.4;run;

data _null_; file print; put 'Case freq_level_order_custom_internal'; run;
data d;input x w;datalines;
-2 1
12 1
.75 1
-10.5 1
2 1
. 1
-2.25 1
10 1
0 1
;
run;
proc format;value ord -2,-2.25='zneg' -10.5='yneg' .75='cfrac' 0='d0' 2='xpos' 10='bpos' 12='apos';run;
proc freq data=d order=internal;format x ord.;weight w;tables x / missing out=o;run;data _null_;set o;file print;put 'LEVEL ' x 12.4;run;

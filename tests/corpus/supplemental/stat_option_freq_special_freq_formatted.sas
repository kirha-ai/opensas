data control;length fmtname $8 label $12;input start label $;end=start;fmtname='Code';datalines;
._ Underscore
. Blank
.A Alpha
.Z Zulu
1 First
2 Second
;
run;
proc format cntlin=control;run;
data sample;input g x;datalines;
.A 1
._ 2
.Z 1
. 2
.A 2
2 1
1 1
;
run;
proc freq data=sample noprint order=freq;format g code.;tables g / missing out=counts outcum;run;data _null_;set counts;file print;key=g;
if g=._ then key=93;else if g=. then key=90;else if g=.A then key=91;else if g=.Z then key=92;
put 'LEVEL ' key 3. '|' count 2. '|' cum_freq 2.;run;

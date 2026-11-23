proc format;value grp 1,2='A' 3='B';run;
data sample;input g x f id;format g grp.;datalines;
1 10 0 101
2 20 1 102
2 30 1 103
3 40 1 104
;
run;
proc freq data=sample noprint;by g;weight f;tables x / out=o;run;data _null_;set o;file print;put 'KEY ' g best4. '|' x '|' count;run;

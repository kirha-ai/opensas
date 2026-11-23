data sample;input g x;datalines;
1 1
1 2
1 3
2 5
3 1
3 1
3 2
3 2
4 9
4 9
;
run;
ods output Modes=result;proc univariate data=sample modes;by g;var x;run;data _null_;file print;set result;put 'MODE ' g 4. '|' mode '|' count;run;

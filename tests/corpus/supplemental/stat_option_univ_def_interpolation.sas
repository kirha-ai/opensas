data sample;input x;datalines;
1
2
8
10
16
31
;
run;
proc univariate data=sample noprint def=1;var x;output out=p pctlpts=20 25 30 50 70 75 pctlpre=p;run;data _null_;file print;set p;put 'Q ' p20 8.2 p25 8.2 p30 8.2 p50 8.2 p70 8.2 p75 8.2;run;

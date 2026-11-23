data sample; input x; datalines;
1
2
3
5
9
10
11
12
;
run;

ods output BasicIntervals=ci;
proc univariate data=sample cibasic(type=lower alpha=.1);var x;run;
data _null_;file print;set ci;if Parameter='Mean' then put 'CL ' Estimate 12.6 LowerCL 12.6;run;

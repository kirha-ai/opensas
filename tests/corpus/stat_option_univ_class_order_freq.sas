proc format; value names 1='A' 2='Z' 3='Q'; run;
data sample; input g x; format g names.; datalines;
2 1
3 4
1 9
3 2
2 7
3 1
;
run;

ods select Moments;
proc univariate data=sample; class g(order=freq); var x; run;

data d; input x; datalines;
1
2
3
4
5
6
7
8
9
10
;
run;
/* BUG-meansoptnoop: ALPHA=0.1 relabels the CLM columns and shifts the limits
   to t(0.95,9)=1.8331129 · SE (3.7449280 / 7.2550720). */
proc means data=d alpha=0.1 clm mean;
  var x;
run;

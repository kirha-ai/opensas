data d; input b x; datalines;
1 1
1 2
2 2
2 3
;
ods output CrossTabFreqs=c OneWayFreqs=o;
proc freq data=d; by b; tables b b*x x*x; run;
proc contents data=c varnum; run; proc print data=c; run;
proc contents data=o varnum; run; proc print data=o; run;
ods output Moments=same Quantiles=same;
proc univariate data=d; var x; run;
proc contents data=same varnum; run;

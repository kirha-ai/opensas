data d; input x y w; datalines;
1 3 1
1 5 2
4 4 0
7 1 -1
;
ods output Moments=m Quantiles=q BasicMeasures=b;
proc univariate data=d; weight w; var x; run;
proc print data=m; run; proc print data=q; run; proc print data=b; run;
ods output OneWayFreqs=o CrossTabFreqs=c;
proc freq data=d; weight w; tables x x*y; run;
proc contents data=o varnum; run; proc print data=o; run;
proc contents data=c varnum; run; proc print data=c; run;

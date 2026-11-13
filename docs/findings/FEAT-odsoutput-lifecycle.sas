data d; input x y; datalines;
1 2
2 4
3 3
;
ods output PearsonCorr=c Moments=m;
proc corr data=d; var x y; run;
proc univariate data=d; var x; run;
%put FIRST_C=%sysfunc(exist(c)) FIRST_M=%sysfunc(exist(m));
ods output OneWayFreqs=o1 OneWayFreqs=o2;
proc freq data=d; tables x; run;
%put O1=%sysfunc(exist(o1)) O2=%sysfunc(exist(o2));
ods output Moments=after;
proc print data=d; run;
proc univariate data=d; var x; run;
%put AFTER=%sysfunc(exist(after));
ods output Moments=empty;
proc univariate data=d(where=(x>99)); var x; run;
%put EMPTY=%sysfunc(exist(empty));
ods output Moments=cl Quantiles=cq BasicMeasures=cb;
proc univariate data=d; class y; var x; run;
proc contents data=cl varnum; run;
proc print data=cl; run;

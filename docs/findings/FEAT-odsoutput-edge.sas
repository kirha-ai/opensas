data d; input b x y w; label x='X label'; datalines;
1 1 3 1
1 2 . 2
1 . 4 0
1 4 5 3
;
ods output PearsonCorr=pc SimpleStats=ss;
proc corr data=d; var x y; weight w; run;
ods output OneWayFreqs=ow;
proc freq data=d; tables x y; run;
ods output Moments=mo Quantiles=qu;
proc univariate data=d; var x; run;
proc print data=pc; run;
proc contents data=pc varnum; run;
proc print data=ss; run;
proc contents data=ss varnum; run;
proc print data=ow; run;
proc contents data=ow varnum; run;
proc print data=qu; run;
ods output OneWayFreqs=o1;
ods output OneWayFreqs=o2;
proc freq data=d; tables x; run;
data _null_; file print; put 'exist_o1=' %sysfunc(exist(o1)) ' exist_o2=' %sysfunc(exist(o2)); run;
ods output Quantiles=none;
proc univariate data=d noprint; var x; run;
data _null_; file print; put 'exist_none=' %sysfunc(exist(none)); run;

data d; x=.; output; run;
ods output Moments=m Quantiles=q BasicMeasures=b;
proc univariate data=d; var x; run;
%put MISSING_M=%sysfunc(exist(m)) MISSING_Q=%sysfunc(exist(q)) MISSING_B=%sysfunc(exist(b));
proc print data=m; run;
data d; input x; datalines;
1
2
4
;
ods output Moments=m Quantiles=q BasicMeasures=b;
proc univariate data=d; var x; run;
data _null_; set m; file print; put _all_; run;

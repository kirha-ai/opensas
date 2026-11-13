data d; input b x y; datalines;
1 1 3
1 2 5
1 4 4
2 3 1
2 5 2
2 7 9
;
proc corr data=d; ods output PearsonCorr=pc SimpleStats=ss; by b; var x y; run;
ods output OneWayFreqs=ow CrossTabFreqs=ct; proc freq data=d; by b; tables x x*y; run;
ods output Moments=mo Quantiles=qu BasicMeasures=bm; proc univariate data=d; by b; var x y; run;
data _null_; file print; set pc; if b=1 and Variable='x' then put 'ODS_CORR=' y 16.12; run;
data _null_; file print; set ss; if b=1 and Variable='x' then put 'ODS_MEAN=' Mean 16.12; run;
data _null_; file print; set ow; if b=1 and x=2 then put 'ODS_CUM=' CumFrequency 1.; run;
data _null_; file print; set ct; if b=1 and _TYPE_='00' then put 'ODS_TOTAL=' Frequency 1.; run;
data _null_; file print; set mo; if b=1 and VarName='x' and Label1='Mean' then put 'ODS_MOMENT=' nValue1 16.12; run;
data _null_; file print; set qu; if b=1 and VarName='x' and Quantile='50% Median' then put 'ODS_MEDIAN=' Estimate; run;
data _null_; file print; set bm; if b=1 and VarName='x' and LocMeasure='Median' then put 'ODS_BASIC=' LocValue; run;

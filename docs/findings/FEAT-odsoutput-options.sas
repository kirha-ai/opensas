data d; input b x y; datalines;
1 1 1
1 1 2
1 2 1
1 2 2
;
ods output CrossTabFreqs=c CrossList=cl List=l;
proc freq data=d; tables x*y / crosslist expected deviation cellchi2 cumcol totpct pearsonres stdres; run;
proc contents data=c varnum; run; proc contents data=cl varnum; run;
ods output CrossTabFreqs=grid;
proc freq data=d; tables b*x*y / expected deviation cellchi2 cumcol totpct; run;
proc contents data=grid varnum; run; proc print data=grid; run;
ods output PearsonCorr=np SimpleStats=ns;
proc corr data=d noprob; var x y; run;
proc contents data=np varnum; run;
ods output OneWayFreqs=allmiss;
proc freq data=d(where=(x>99)); tables x; run;

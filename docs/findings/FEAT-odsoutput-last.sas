data d; input x y; datalines;
1 2
2 3
4 1
;
ods output PearsonCorr=pc SimpleStats=ss;
proc corr data=d; var x y; run;
%put ODS_LAST=&syslast;
proc print; run;
ods output OneWayFreqs=o1 OneWayFreqs=o2;
proc freq data=d; tables x; run;
%put FREQ_LAST=&syslast;
proc print; run;

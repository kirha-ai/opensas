data d; input a $ b w; datalines;
A 1 1
A 2 2
B 1 1
. 2 1
;
ods output OneWayFreqs=o CrossTabFreqs=c;
proc freq data=d; tables a / missprint nocum nopercent; tables a*b / expected deviation cellchi2 norow nocol nopercent; run;
proc contents data=o varnum; run; proc print data=o; run;
proc contents data=c varnum; run; proc print data=c; run;
ods output CrossTabFreqs=l;
proc freq data=d; tables a*b / list; run;
proc contents data=l varnum; run; proc print data=l; run;
ods output OneWayFreqs=n;
proc freq data=d; weight w; tables a; run;
proc contents data=n varnum; run; proc print data=n; run;

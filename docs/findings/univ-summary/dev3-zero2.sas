data z;input x w;datalines;
0 0
10 0
20 0
100 0
;
proc univariate data=z noprint;var x;weight w;output out=o n=n css=css median=med pctlpts=0 25 50 75 100 pctlpre=p;run;
data _null_;set o;file print;put n= css= med= p0= p25= p50= p75= p100=;run;

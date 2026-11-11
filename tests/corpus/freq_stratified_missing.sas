/* FEAT-freq-stratified: independent SAS evidence /tmp/opensas-stat-batch2/FEAT-freq-stratified/adapter_missing.sas; displayed numeric tolerance .00005, I2 percent .005. */
options nosyntaxcheck; ods graphics off;
data scores;
input r c n;
datalines;
. 1 6
. 2 16
2 1 2
2 2 4
;
proc freq data=scores; tables r*c / missing cmh trend jt agree; weight n; run;
proc freq data=scores; tables c*r / missing cmh trend jt agree; weight n; run;

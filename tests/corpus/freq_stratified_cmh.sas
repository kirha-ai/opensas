/* FEAT-freq-stratified: independent SAS evidence /tmp/opensas-stat-batch2/FEAT-freq-stratified/kernels.sas; displayed numeric tolerance .00005, I2 percent .005. */
options nosyntaxcheck;
ods graphics off;
data asym;
input r c n;
datalines;
1 1 18
1 2 3
1 3 1
2 1 7
2 2 12
2 3 4
3 1 2
3 2 9
3 3 24
;
proc freq data=asym; tables r*c / agree(details ac1 pabak printkwts) jt cmh; test kappa wtkappa; weight n; run;
proc freq data=asym; tables r*c / agree(wt=fc nullkappa=.2 nullwtkappa=.3 dfsym=adjust) scores=table; weight n; run;
data trend;
input r c n;
datalines;
1 1 8
1 2 17
3 1 12
3 2 11
8 1 20
8 2 4
;
proc freq data=trend; tables r*c / trend jt; weight n; run;
data drugs;
input a b c n;
datalines;
1 1 1 6
1 1 2 16
1 2 1 2
1 2 2 4
2 1 1 2
2 1 2 4
2 2 1 6
2 2 2 6
;
proc freq data=drugs; tables a*b*c / agree cmh(gailsimon mf bdt qor i2); weight n; run;
data migraine;
input s r c n;
datalines;
1 1 1 16
1 1 2 11
1 2 1 5
1 2 2 20
2 1 1 12
2 1 2 16
2 2 1 7
2 2 2 19
;
proc freq data=migraine; tables s*r*c / cmh(gailsimon mf bdt qor i2); weight n; run;

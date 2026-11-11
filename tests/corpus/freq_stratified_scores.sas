/* FEAT-freq-stratified: independent SAS evidence /tmp/opensas-stat-batch2/FEAT-freq-stratified/pooled_edges.sas; displayed numeric tolerance .00005, I2 percent .005. */
options nosyntaxcheck; ods graphics off;
data agreement;
input s r c n;
datalines;
1 1 1 18
1 1 2 3
1 1 3 1
1 2 1 7
1 2 2 12
1 2 3 4
1 3 1 2
1 3 2 9
1 3 3 24
2 1 1 6
2 1 2 4
2 1 3 2
2 2 1 1
2 2 2 9
2 2 3 5
2 3 1 3
2 3 2 2
2 3 3 7
;
proc freq data=agreement; tables s*r*c / agree(wt=fc details) cmh scores=rank noprint; weight n; run;
proc freq data=agreement; tables s*r*c / agree(wt=fc) cmh scores=ridit noprint; weight n; run;
proc freq data=agreement; tables s*r*c / agree(wt=fc) cmh scores=modridit noprint; weight n; run;
data perfect;
input s r c n;
datalines;
1 1 1 9
1 1 2 0
1 2 1 0
1 2 2 6
2 1 1 6
2 1 2 16
2 2 1 2
2 2 2 4
;
proc freq data=perfect; tables s*r*c / agree cmh(gailsimon i2) noprint; weight n / zeros; run;

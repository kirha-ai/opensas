/* FEAT-freq-stratified: independent SAS evidence /tmp/opensas-stat-batch2/FEAT-freq-stratified/adapter_margins.sas; displayed numeric tolerance .00005, I2 percent .005. */
options nosyntaxcheck; ods graphics off;
data sparse;
input s r c n;
datalines;
1 1 1 16
1 1 2 11
1 2 1 5
1 2 2 20
2 1 1 0
2 1 2 0
2 2 1 6
2 2 2 8
3 1 1 12
3 1 2 16
3 2 1 7
3 2 2 19
;
proc freq data=sparse; tables s*r*c / cmh(gailsimon qor) commonriskdiff(cl=(mh mr score newcombe) printwts) noprint; weight n / zeros; run;

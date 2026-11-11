/* FEAT-freq-stratified: independent SAS evidence /tmp/opensas-stat-batch2/FEAT-freq-stratified/common.sas; displayed numeric tolerance .00005, I2 percent .005. */
options nosyntaxcheck; ods graphics off;
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
run;
proc freq data=migraine; tables s*r*c / commonriskdiff(cl=(mh k mr score newcombe newcombemr) test=(mh mr score) printwts) alpha=.1; weight n; run;
proc freq data=migraine; tables s*r*c / commonriskdiff(cl=mr test=mr(var=sample) correct=no column=2 printwts) alpha=.1; weight n; run;
proc freq data=migraine; tables s*r*c / commonriskdiff(cl=score test=score column=2) alpha=.1; weight n; run;

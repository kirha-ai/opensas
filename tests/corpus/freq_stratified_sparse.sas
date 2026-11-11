/* FEAT-freq-stratified: independent SAS evidence /tmp/opensas-stat-batch2/FEAT-freq-stratified/sparse_q.sas; displayed numeric tolerance .00005, I2 percent .005. */
options nosyntaxcheck; ods graphics off; 
data patterns; input v0 v1 v2 v3 v4 v5 v6 v7 v8 v9 v10 v11 n; datalines;
1 1 1 1 1 1 1 1 1 1 1 2 10
2 2 2 2 2 2 2 2 2 2 2 1 20
1 1 1 1 1 1 1 1 1 1 1 1 7
; run;
proc freq data=patterns; tables v0*v1*v2*v3*v4*v5*v6*v7*v8*v9*v10*v11 / agree noprint; weight n; run;

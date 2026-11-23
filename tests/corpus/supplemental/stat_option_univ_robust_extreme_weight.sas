data d;input z f;x=z*1e308;datalines;
0 7
.257 1
;
run;proc univariate data=d noprint;var x;weight f;output out=q gini=g;run;

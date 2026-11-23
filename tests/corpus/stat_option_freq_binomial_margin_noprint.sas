data d;input x n;datalines;
1 3
2 7
;
run;
proc freq data=d noprint;weight n;tables x/binomial(equiv p=.2 margin=.2);run;

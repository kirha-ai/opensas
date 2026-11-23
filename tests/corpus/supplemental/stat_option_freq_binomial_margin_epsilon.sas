/* expect-rc: 1 */
data d;input x n;datalines;
1 3
2 7
;
run;
proc freq data=d;weight n;tables x/binomial(equiv p=.3 margin=.30000000000000004);run;

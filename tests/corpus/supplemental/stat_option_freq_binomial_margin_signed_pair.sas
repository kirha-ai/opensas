/* expect-rc: 1 */
data d;input x n;datalines;
1 3
2 7
;
run;
proc freq data=d;weight n;tables x/binomial(noninf sup equiv p=.01 margin=(.05,.1));run;

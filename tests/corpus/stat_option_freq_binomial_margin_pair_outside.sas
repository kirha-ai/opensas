/* expect-rc: 1 */
data d;input x n;datalines;
1 3
2 7
;
run;
proc freq data=d;weight n;tables x/binomial(margin=(-100,0));run;

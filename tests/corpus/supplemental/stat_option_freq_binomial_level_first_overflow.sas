/* expect-rc: 1 */
data d;length x $8;input x $ n;datalines;
a 3
bb 7
ccc 9
;
run;
proc freq data=d;weight n;tables x/binomial(level=9223372036854775296);run;

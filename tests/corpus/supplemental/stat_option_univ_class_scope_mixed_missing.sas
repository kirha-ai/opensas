/* expect-rc: 1 */
data d;input a b y;datalines;
.A .Z 1
.A 1 2
1 .Z 4
1 2 8
._ ._ 16
1 1 32
;
run;
proc univariate data=d;class a(missing) b / missing;var y;run;

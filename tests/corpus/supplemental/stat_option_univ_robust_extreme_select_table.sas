/* expect-rc: 1 */
data d;input z;x=1;y=z*1e308;datalines;
0
0
0
0
0
0
0
.257
;
run;proc univariate data=d noprint outtable=t;var x y;run;

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
run;proc univariate data=d noprint ;var x y;output out=q normaltest=g h;run;

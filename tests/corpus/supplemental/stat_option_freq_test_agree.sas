data agreement;input x y w;datalines;
1 1 15
1 2 1
1 3 4
2 1 2
2 2 10
2 3 4
3 1 1
3 2 3
3 3 12
;
run;
proc freq data=agreement;weight w;tables x*y / noprint;test agree;run;

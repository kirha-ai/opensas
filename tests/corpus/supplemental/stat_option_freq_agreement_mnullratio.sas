data sample;input x y w;datalines;
1 1 16
1 2 11
2 1 5
2 2 20
;
run;
proc freq data=sample;weight w / zeros;tables x*y / noprint agree(mnullratio=2);run;

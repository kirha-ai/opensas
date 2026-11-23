data d;input g h r c w;datalines;
1 1 1 1 2
1 1 2 2 3
2 2 1 . 1
2 2 . 2 2
3 2 1 1 0
3 2 2 2 0
;
run;
proc freq data=d;weight w / zeros;tables g*h*r*c / chisq noprint;run;

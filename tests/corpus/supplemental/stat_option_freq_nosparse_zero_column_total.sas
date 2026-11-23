data d;input r c w;datalines;
1 1 2
2 1 3
1 2 0
2 2 0
;
run;
proc freq data=d;weight w / zeros;tables r*c / crosslist nosparse;run;

data sample;input g r c w;datalines;
1 1 1 4
1 1 2 1
1 2 1 2
1 2 2 3
2 1 1 3
2 2 2 7
2 3 3 0
;
run;
proc freq data=sample ;where g=1;weight w / zeros;tables r*c / nocol;run;

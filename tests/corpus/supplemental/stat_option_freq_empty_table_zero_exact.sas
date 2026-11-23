data d;input r c w;datalines;
1 1 0
1 2 0
2 1 0
2 2 0
;
run;
proc freq data=d;weight w / zeros;tables r*c;exact fisher;run;

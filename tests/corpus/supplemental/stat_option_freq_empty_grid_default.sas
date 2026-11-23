data d;input g h r c w;datalines;
0 0 1 1 2
0 0 2 2 3
1 1 1 1 3
1 1 2 2 4
;
run;
proc freq data=d;weight w;tables g*h*r*c;run;

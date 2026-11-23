data d;input r c w;datalines;
0 0 1
0 1 1
;
run;
proc freq data=d;weight w;tables r*r / chisq;run;

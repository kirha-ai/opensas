data sample;input r c w;datalines;
1 1 1
1 2 8
1 3 8
2 1 1
2 2 8
2 3 8
;
run;
proc freq data=sample;weight w;tables r*c / chisq;run;

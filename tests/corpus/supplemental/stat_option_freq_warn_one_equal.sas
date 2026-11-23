data sample;input r w;datalines;
1 1
2 2
3 3
;
run;
proc freq data=sample;weight w;tables r / chisq;run;

data sample;input r w;datalines;
1 14
2 4
3 2
;
run;
proc freq data=sample;weight w;tables r / chisq(testp=(.7 .2 .1));run;

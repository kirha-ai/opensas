data sample;input r w;datalines;
1 4
2 24
3 24
4 24
5 24
;
run;
proc freq data=sample;weight w;tables r / chisq(testp=(.04 .24 .24 .24 .24));run;

data d;input r c w;datalines;
1 . 1
2 . 1
. 1 1
. 2 1
;
run;
proc freq data=d;weight w;tables r*c / chisq ;run;

data d;input g r c w;datalines;
1 1 1 2
1 2 2 3
2 1 . 1
2 . 2 2
. 1 1 3
. 2 2 4
;
run;
proc freq data=d;weight w;tables g*r*c / chisq missprint;run;

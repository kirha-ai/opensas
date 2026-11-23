data trial;input r c w;datalines;
1 1 16
1 2 11
2 1 5
2 2 20
;
run;
proc freq data=trial;weight w;tables r*c / noprint or(cl=score(correct=no));run;

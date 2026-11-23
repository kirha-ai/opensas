data sample;input r c n;datalines;
1 1 1
1 2 4
2 1 3
2 2 2
;
run;
proc freq data=sample;weight n / zeros;tables r*c / noprint;exact measures;run;

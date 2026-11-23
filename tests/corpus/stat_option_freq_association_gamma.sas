data sample;input r c w;datalines;
1 2 12
1 7 5
1 40 3
10 2 4
10 7 17
10 40 6
100 2 2
100 7 8
100 40 13
;
run;
proc freq data=sample;weight w;tables r*c / noprint measures(cl);test gamma;run;

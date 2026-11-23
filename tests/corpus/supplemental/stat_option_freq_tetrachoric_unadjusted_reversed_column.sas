data sample;input r c w;datalines;
1 1 5
1 2 0
2 1 10
2 2 5
;
run;
proc freq data=sample;weight w / zeros;tables r*c / noprint plcorr;run;

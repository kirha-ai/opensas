data sample;input r c w;datalines;
1 1 0
1 2 4
2 1 8
2 2 12
;
run;
proc freq data=sample;weight w / zeros;tables r*c / noprint plcorr;run;

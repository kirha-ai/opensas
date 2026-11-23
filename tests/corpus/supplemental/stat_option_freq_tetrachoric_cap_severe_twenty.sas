data sample;input r c w;datalines;
1 1 0
1 2 9
2 1 11
2 2 3
;
run;
proc freq data=sample;weight w / zeros;tables r*c / noprint plcorr(maxiter=20);run;

data trial;input s r c w;datalines;
1 1 1 16
1 1 2 11
1 2 1 5
1 2 2 20
2 1 1 7
2 1 2 19
2 2 1 12
2 2 2 16
;
run;
proc freq data=trial;where s=1;weight w;tables r*c / trend noprint;run;

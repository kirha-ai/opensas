data sample;input x w;datalines;
1 1
2 1
2 1
4 1
5 1
7 1
8 1
9 1
;
run;
ods select Modes BasicIntervals TestsForNormality LocationCounts TrimmedMeans WinsorizedMeans RobustScale ExtremeValues Frequencies;

proc univariate data=sample trimmed=1 all nextrval=1; var x; run;

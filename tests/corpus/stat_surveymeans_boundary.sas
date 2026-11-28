/* STAT-SURVEYMEANS-001: boundaries. Invented data. Expected listing is the
 * SAS 9.4 (SAS/STAT 15.4) output of this exact program (reference run
 * 2026-11-28): a negative lower confidence limit keeps the 10-wide column
 * (one decimal fewer for the sign: -9.0191896 beside 3.01918955); when
 * every weight is nonpositive SAS writes "NOTE: No observations." and
 * prints nothing for the step.
 */
options nodate nonumber nocenter linesize=160;
title 'F negative clm';
data f; input y; datalines;
-5
1
-3
2
-10
;
proc surveymeans data=f; var y; run;
title 'H all excluded';
data h; input y w; datalines;
1 0
2 .
;
proc surveymeans data=h; var y; weight w; run;

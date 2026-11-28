/* STAT-SCORE-001: PROC SCORE default scoring (SAS/STAT 15.4 ch.109,
   pp.8908-8911). DATA= raw data, SCORE= constructed coefficients with
   _TYPE_='SCORE' (the default TYPE), OUT= data set holding every DATA=
   variable followed by one score variable per _NAME_; VAR names the scoring
   variables. PROC SCORE prints nothing; PROC PRINT shows the result.
   Data: the published 12-observation Fitness subset of the chapter.
   Expected: the score values of the SAS reference listing of this program
   (AGE_WGT = Age - Weight, RUN_RST = RunPulse - RestPulse, TOTAL = sum of
   the five variables). TOTAL carries an explicit 8.2 format so that the
   listing does not depend on PROC PRINT's decimal alignment of unformatted
   values, and the mixed-case DATA= variables are not printed (PROC PRINT
   heading splitting is not part of this ticket). */
options nocenter linesize=160 nodate nonumber;
title;
data Fitness;
input Age Weight Oxygen RunTime RestPulse RunPulse @@;
datalines;
44 89.47 44.609 11.37 62 178 40 75.07 45.313 10.07 62 185
44 85.84 54.297 8.65 45 156 42 68.15 59.571 8.17 40 166
38 89.02 49.874 9.22 55 178 47 77.45 44.811 11.63 58 176
40 75.98 45.681 11.95 70 176 43 81.19 49.091 10.85 64 162
44 81.42 39.442 13.08 63 174 38 81.87 60.055 8.63 48 170
44 73.03 50.541 10.13 45 168 45 87.66 37.388 14.03 56 186
;
run;
data A;
input _type_ $ _name_ $
Age Weight RunTime RunPulse RestPulse;
datalines;
SCORE AGE_WGT 1 -1 0 0 0
SCORE RUN_RST 0 0 0 1 -1
SCORE TOTAL 1 1 1 1 1
;
proc score data=Fitness score=A out=B;
var Age Weight RunTime RunPulse RestPulse;
run;
proc print data=B;
var Age AGE_WGT RUN_RST TOTAL;
format TOTAL 8.2;
run;

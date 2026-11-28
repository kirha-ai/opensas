/* STAT-SCORE-001: PROC SCORE BY processing (SAS/STAT 15.4 ch.109,
   pp.8909-8910). Both the DATA= observations and the SCORE= coefficient rows
   carry the BY variable grp with identical groups 1 and 2; each DATA= group
   is scored with the coefficients of the matching SCORE= group and the OUT=
   data set keeps the group boundaries. A third coefficient group (grp=3)
   absent from DATA= is allowed without NOTSORTED and is not used. Last, a
   DATA= set without the BY variable is scored by every coefficient group
   (grp 1 and 2, coefficient 1 and 2 on x) and grp is appended after the ID
   variable.
   Data: the published Fitness subset of the chapter (first four
   observations). Expected: the score values of the SAS reference listing of
   the two-group program (AGE_WGT, RUN_RST, TOTAL identical in both groups);
   the extra-group and DATA=-without-BY cases are hand mathematics of
   p.8910 (T = grp * x). Listing spacing follows the opensas PROC PRINT
   conventions. */
options nocenter linesize=160 nodate nonumber;
title;
data Fitness;
input Age Weight Oxygen RunTime RestPulse RunPulse @@;
datalines;
44 89.47 44.609 11.37 62 178 40 75.07 45.313 10.07 62 185
44 85.84 54.297 8.65 45 156 42 68.15 59.571 8.17 40 166
;
data A;
input _type_ $ _name_ $
Age Weight RunTime RunPulse RestPulse;
datalines;
SCORE AGE_WGT 1 -1 0 0 0
SCORE RUN_RST 0 0 0 1 -1
SCORE TOTAL 1 1 1 1 1
;
data A; set A; do grp=1 to 3; output; end; run;
proc sort data=A; by grp; run;
data In; set Fitness; do grp=1 to 2; output; end; run;
proc sort data=In; by grp; run;
proc score data=In score=A out=B;
by grp;
var Age Weight RunTime RunPulse RestPulse;
run;
proc print data=B;
var grp Age AGE_WGT RUN_RST TOTAL;
format TOTAL 8.2;
run;
data X; input id $ x; datalines;
a 1
b 5
;
data C; input grp _type_ $ _name_ $ x; datalines;
1 SCORE T 1
2 SCORE T 2
;
proc score data=X score=C out=D;
by grp;
var x;
id id;
run;
proc print data=D;
run;

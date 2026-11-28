/* STAT-CATMOD-001: PROC CATMOD BY groups. Two BY groups hold identical copies
 * of the published SAS/STAT 15.4 Chapter 36 cold-incidence data, so both
 * groups print the same analysis; BY closes the interactive procedure.
 * Values were checked token-for-token against the SAS listing; the BY line
 * follows the house BY-line layout (centered, as in stat_anova_by). */
options nodate nonumber nocenter linesize=160;
title;
data colds;
input sex $ residence $ periods count @@;
datalines;
female rural 0 45 female rural 1 64 female rural 2 71
female urban 0 80 female urban 1 104 female urban 2 116
male rural 0 84 male rural 1 124 male rural 2 82
male urban 0 106 male urban 1 117 male urban 2 87
;
run;
data grouped; set colds; do cohort=1 to 2; output; end; run;
proc sort data=grouped; by cohort; run;
proc catmod data=grouped;
by cohort;
weight count;
response means;
model periods=sex residence sex*residence / design;
run;
quit;

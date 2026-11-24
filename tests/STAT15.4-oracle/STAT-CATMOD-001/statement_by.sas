/* STAT-CATMOD-001: CATMOD — Data input, variable roles, and basic options
 * Source: S154 / Chapter 36 / `PROC CATMOD Statement` (PDF pp. 2191–2192); S154 / Chapter 36 / `BY Statement` (PDF pp. 2192–2193); S154 / Chapter 36 / `POPULATION Statement` (PDF pp. 2208–2211); S154 / Chapter 36 / `WEIGHT Statement` (PDF p. 2220); S154 / Chapter 36 / `Missing Values` (PDF p. 2220); S154 / Chapter 36 / `Input Data Sets` (PDF pp. 2220–2223); S154 / Chapter 36 / `Ordering of Populations and Responses` (PDF pp. 2223–2224).
 * Discriminates: Two BY groups with identical weighted cold-frequency populations.
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

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

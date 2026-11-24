/* STAT-SCORE-001: SCORE — Data input, variable roles, and basic options
 * Source: S154 / Chapter 109 / `PROC SCORE Statement` (PDF pp. 8908–8909); S154 / Chapter 109 / `BY Statement` (PDF pp. 8909–8910); S154 / Chapter 109 / `ID Statement` (PDF p. 8910); S154 / Chapter 109 / `VAR Statement` (PDF pp. 8910–8911); S154 / Chapter 109 / `Missing Values` (PDF p. 8911).
 * Discriminates: Two explicit BY groups contain identical inputs, exposing group boundaries and per-group results.
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

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
proc print data=A;
title 'Constructed Scoring Example';
title2 'Scoring Coefficients';
run;
data A; set A; do _oracle_by=1 to 2; output; end; run;
proc sort data=A; by _oracle_by; run;
data _oracle_input; set Fitness; do _oracle_by=1 to 2; output; end; run;
proc sort data=_oracle_input; by _oracle_by; run;
proc score data=_oracle_input score=A out=B;
by _oracle_by;
var Age Weight RunTime RunPulse RestPulse;
run;
proc print data=B;
title2 'Scored Data';
run;

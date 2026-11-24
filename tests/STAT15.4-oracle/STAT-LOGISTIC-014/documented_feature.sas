/* STAT-LOGISTIC-014: LOGISTIC — CONTRAST / ESTIMATE / TEST
 * Source: S154 / Chapter 79 / `CONTRAST Statement` (PDF pp. 5855–5858); S154 / Chapter 79 / `ESTIMATE Statement` (PDF pp. 5860–5861); S154 / Chapter 79 / `TEST Statement` (PDF pp. 5902–5903).
 * Discriminates: Example 79.2: Logistic Modeling with Categorical Predictors; explicit statements: CONTRAST, ESTIMATE
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data Neuralgia;
input Treatment $ Sex $ Age Duration Pain $ @@;
datalines;
P F 68 1 No B M 74 16 No P F 67 30 No
P M 66 26 Yes B F 67 28 No B F 77 16 No
A F 71 12 No B F 72 50 No B F 76 9 Yes
A M 71 17 Yes A F 63 27 No A F 69 18 Yes
B F 66 12 No A M 62 42 No P F 64 1 Yes
A F 64 17 No P M 74 4 No A F 72 25 No
P M 70 1 Yes B M 66 19 No B M 59 29 No
A F 64 30 No A M 70 28 No A M 69 1 No
B F 78 1 No P M 83 1 Yes B F 69 42 No
B M 75 30 Yes P M 77 29 Yes P F 79 20 Yes
A M 70 12 No A F 69 12 No B F 65 14 No
B M 70 1 No B M 67 23 No A M 76 25 Yes
P M 78 12 Yes B M 77 1 Yes B F 69 24 No
P M 66 4 Yes P F 65 29 No P M 60 26 Yes
A M 78 15 Yes B M 75 21 Yes A F 67 11 No
P F 72 27 No P F 70 13 Yes A M 75 6 Yes
B F 65 7 No P F 68 27 Yes P M 68 11 Yes
P M 67 17 Yes B M 70 22 No A M 65 15 No
P F 67 1 Yes A M 67 10 No P F 72 11 Yes
A F 74 1 No B M 80 21 Yes A F 69 3 No
;
proc logistic data=Neuralgia;
class Treatment Sex;
model Pain= Treatment Sex Treatment*Sex Age Duration / expb;
run;
proc logistic data=Neuralgia;
class Treatment Sex;
model Pain=Treatment|Sex@2 Age Duration
/selection=forward expb;
run;
ods graphics on;
proc logistic data=Neuralgia plots(only)=(oddsratio(range=clip));
class Treatment Sex /param=ref;
model Pain= Treatment Sex Age / noor;
oddsratio Treatment;
oddsratio Sex;
oddsratio Age;
contrast 'Pairwise A vs P' Treatment 1 0 / estimate=exp;
contrast 'Pairwise B vs P' Treatment 0 1 / estimate=exp;
contrast 'Pairwise A vs B' Treatment 1 -1 / estimate=exp;
contrast 'Female vs Male' Sex 1 / estimate=exp;
effectplot / at(Sex=all) noobs;
effectplot slicefit(sliceby=Sex plotby=Treatment) / noobs;
run;

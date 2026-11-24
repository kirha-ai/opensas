/* STAT-RSREG-005: RSREG — Searching for Multiple Response Conditions / Handling Covariates / Computational Method
 * Source: S154 / Chapter 108 / `Searching for Multiple Response Conditions` (PDF pp. 8882–8884); S154 / Chapter 108 / `Handling Covariates` (PDF pp. 8884–8885); S154 / Chapter 108 / `Computational Method` (PDF pp. 8885–8886).
 * Discriminates: Example 108.2: Response Surface Analysis with Covariates
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data Experiment;
input Day Grade Time Temp Pressure Yield;
datalines;
1 67 -1 -1 -1 32.98
1 68 -1 1 1 47.04
1 70 1 -1 1 67.11
1 66 1 1 -1 26.94
1 74 0 0 0 103.22
1 68 0 0 0 42.94
2 75 -1 -1 1 122.93
2 69 -1 1 -1 62.97
2 70 1 -1 -1 72.96
2 71 1 1 1 94.93
2 72 0 0 0 93.11
2 74 0 0 0 112.97
3 69 1.633 0 0 78.88
3 67 -1.633 0 0 52.53
3 68 0 1.633 0 68.96
3 71 0 -1.633 0 92.56
3 70 0 0 1.633 88.99
3 72 0 0 -1.633 102.50
3 70 0 0 0 82.84
3 72 0 0 0 103.12
;
proc rsreg data=Experiment;
model Yield = Time Temp Pressure;
run;
data Experiment;
set Experiment;
d1 = (Day = 1);
d2 = (Day = 2);
d3 = (Day = 3);
ods graphics on;
proc rsreg data=Experiment plots=all;
model Yield = d1-d3 Grade Time Temp Pressure / covar=4;
run;
ods graphics off;
run;
quit;

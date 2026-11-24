/* STAT-ICPHREG-005: ICPHREG — BASELINE / Model and Likelihood / Computational Details
 * Source: S154 / Chapter 70 / `BASELINE Statement` (PDF pp. 5214–5217); S154 / Chapter 70 / `Model and Likelihood` (PDF pp. 5229–5231); S154 / Chapter 70 / `Computational Details` (PDF pp. 5233–5235).
 * Discriminates: Example 70.2: Plotting Predicted Survival and Cumulative Hazard Functions; explicit statements: BASELINE
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data hiv;
input Left Right Stage Dose CdLow CdHigh;
if (Left=0) then Left=.;
if (Right>=26) then Right=.;
datalines;
0 16 0 0 0 1
15 26 0 0 0 1
12 26 0 0 0 1
17 26 0 0 0 1
13 26 0 0 0 1
0 24 0 0 1 0
6 26 0 1 1 0
0 15 0 1 1 0
14 26 0 1 1 0
12 26 0 1 1 0
13 26 0 1 0 1
12 26 0 1 1 0
12 26 0 1 1 0
0 18 0 1 0 1
0 14 0 1 0 1
0 17 0 1 1 0
0 15 0 1 1 0
3 26 1 0 0 1
4 26 1 0 0 1
1 11 1 0 0 1
13 19 1 0 0 1
0 6 1 0 0 1
0 11 1 1 0 0
6 26 1 1 0 0
0 6 1 1 0 0
2 12 1 1 0 0

1 17 1 1 1 0
0 14 1 1 0 0
0 25 1 1 0 1
2 11 1 1 0 0
0 14 1 1 0 0
;
run;
ods graphics on;
proc icphreg data=hiv plot=surv;
class Stage / desc;
model (Left, Right) = Stage / basehaz=splines;
run;
data cov;
Stage=0;
output;
Stage=1;
output;
run;
proc icphreg data=hiv plot=surv;
class Stage / desc;
model (Left, Right) = Stage / basehaz=splines;
baseline covariates=cov;
run;
proc icphreg data=hiv plot=cumhaz;
class Stage / desc;
model (Left, Right) = Stage / basehaz=splines;
baseline covariates=cov;
run;

/* STAT-ICPHREG-001: ICPHREG — Data input, variable roles, and basic options
 * Source: S154 / Chapter 70 / `PROC ICPHREG Statement` (PDF pp. 5207–5214); S154 / Chapter 70 / `BY Statement` (PDF pp. 5217–5218); S154 / Chapter 70 / `FREQ Statement` (PDF p. 5221); S154 / Chapter 70 / `ID Statement` (PDF pp. 5223–5224); S154 / Chapter 70 / `STRATA Statement` (PDF pp. 5228–5229); S154 / Chapter 70 / `Missing Values` (PDF p. 5246).
 * Discriminates: Verified default procedure context
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
proc icphreg data=hiv;
class Stage Dose / desc;
model (Left, Right) = Stage Dose;
run;
proc icphreg data=hiv ithistory;
class Stage Dose / desc;
model (Left, Right) = Stage Dose / basehaz=pch(intervals=(10));
run;
proc icphreg data=hiv;
class Stage / desc;
model (Left, Right) = Stage / basehaz=pch(intervals=(10));
hazardratio Stage;
run;

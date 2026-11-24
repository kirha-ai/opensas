/* STAT-TRANSREG-007: TRANSREG — Controlling the Number of Iterations / Using the REITERATE Algorithm Option / Avoiding Constant Transformations
 * Source: S154 / Chapter 126 / `Controlling the Number of Iterations` (PDF pp. 10476–10477); S154 / Chapter 126 / `Using the REITERATE Algorithm Option` (PDF pp. 10477–10478); S154 / Chapter 126 / `Avoiding Constant Transformations` (PDF pp. 10478–10479).
 * Discriminates: Example 126.2: Box-Cox Transformations
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

title 'Yarn Strength';
proc format;
value a -1 = 8 0 = 9 1 = 10;
value l -1 = 250 0 = 300 1 = 350;
value o -1 = 40 0 = 45 1 = 50;
run;
data yarn;
input Fail Amplitude Length Load @@;
format amplitude a. length l. load o.;
label fail = 'Time in Cycles until Failure';
datalines;
674 -1 -1 -1 370 -1 -1 0 292 -1 -1 1 338 0 -1 -1
266 0 -1 0 210 0 -1 1 170 1 -1 -1 118 1 -1 0
90 1 -1 1 1414 -1 0 -1 1198 -1 0 0 634 -1 0 1
1022 0 0 -1 620 0 0 0 438 0 0 1 442 1 0 -1
332 1 0 0 220 1 0 1 3636 -1 1 -1 3184 -1 1 0
2000 -1 1 1 1568 0 1 -1 1070 0 1 0 566 0 1 1
1140 1 1 -1 884 1 1 0 360 1 1 1
;
ods graphics on;
proc transreg details data=yarn ss2
plots=(transformation(dependent) obp);
model BoxCox(fail / convenient lambda=-2 to 2 by 0.05) =
qpoint(length amplitude load);
run;

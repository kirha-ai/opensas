/* STAT-MI-012: MI — MCMC Method Specifications / Checking Convergence in MCMC
 * Source: S154 / Chapter 82 / `MCMC Method Specifications` (PDF pp. 6473–6474); S154 / Chapter 82 / `Checking Convergence in MCMC` (PDF pp. 6474–6476).
 * Discriminates: Example 82.11: Checking Convergence in MCMC
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data Fitness1;
input Oxygen RunTime RunPulse @@;
datalines;
44.609 11.37 178 45.313 10.07 185
54.297 8.65 156 59.571 . .
49.874 9.22 . 44.811 11.63 176
. 11.95 176 . 10.85 .
39.442 13.08 174 60.055 8.63 170
50.541 . . 37.388 14.03 186
44.754 11.12 176 47.273 . .
51.855 10.33 166 49.156 8.95 180
40.836 10.95 168 46.672 10.00 .
46.774 10.25 . 50.388 10.08 168
39.407 12.63 174 46.080 11.17 156
45.441 9.63 164 . 8.92 .
45.118 11.08 . 39.203 12.88 168
45.790 10.47 186 50.545 9.93 148
48.673 9.40 186 47.920 11.50 170
47.467 10.50 170
;
run;
ods graphics on;
proc mi data=Fitness1 seed=501213 nimpute=5 mu0=50 10 180;
mcmc plots=(trace(mean(Oxygen)) acf(mean(Oxygen)));
var Oxygen RunTime RunPulse;
run;

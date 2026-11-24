/* STAT-GENMOD-001: GENMOD — Data input, variable roles, and basic options
 * Source: S154 / Chapter 51 / `PROC GENMOD Statement` (PDF pp. 3509–3514); S154 / Chapter 51 / `BY Statement` (PDF pp. 3525–3526); S154 / Chapter 51 / `FREQ Statement` (PDF p. 3541); S154 / Chapter 51 / `STRATA Statement` (PDF pp. 3565–3567); S154 / Chapter 51 / `WEIGHT Statement` (PDF p. 3567); S154 / Chapter 51 / `Missing Values` (PDF p. 3616).
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

data nor;
input x y;
datalines;
0 5
0 7
0 9
1 7
1 10
1 8
2 11
2 9
3 16
3 13
3 14
4 25
4 24
5 34
5 32
5 30
;
data _oracle_input; set nor; do _oracle_by=1 to 2; output; end; run;
proc sort data=_oracle_input; by _oracle_by; run;
proc genmod data=_oracle_input;
by _oracle_by;
model y = x / dist = normal
link = log;
output out = Residuals
pred = Pred
resraw = Resraw
reschi = Reschi
resdev = Resdev
stdreschi = Stdreschi
stdresdev = Stdresdev
reslik = Reslik;
run;

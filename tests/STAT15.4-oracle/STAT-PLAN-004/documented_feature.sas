/* STAT-PLAN-004: PLAN — TREATMENTS / Using PROC PLAN Interactively / Specifying Factor Structures
 * Source: S154 / Chapter 93 / `TREATMENTS Statement` (PDF pp. 7594–7595); S154 / Chapter 93 / `Using PROC PLAN Interactively` (PDF p. 7595); S154 / Chapter 93 / `Specifying Factor Structures` (PDF pp. 7597–7599).
 * Discriminates: Getting Started: PLAN Procedure; explicit statements: TREATMENTS
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data Unrandomized;
do Unit=1 to 12;
if (Unit <= 6) then Treatment=1;
else Treatment=2;
output;
end;
run;
proc plan seed=27371;
factors Unit=12;
output data=Unrandomized out=Randomized;
run;
proc sort data=Randomized;
by Unit;
run;
proc print;
run;
proc plan seed=27371;
factors Unit=12;
treatments Treatment=12 cyclic (1 1 1 1 1 1 2 2 2 2 2 2);
output out=Randomized;
run;

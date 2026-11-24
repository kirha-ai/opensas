/* STAT-PLAN-001: PLAN — Data input, variable roles, and basic options
 * Source: S154 / Chapter 93 / `PROC PLAN Statement` (PDF pp. 7588–7589).
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

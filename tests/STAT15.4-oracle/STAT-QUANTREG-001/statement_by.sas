/* STAT-QUANTREG-001: QUANTREG — Data input, variable roles, and basic options
 * Source: S154 / Chapter 103 / `proc quantreg Statement` (PDF pp. 8372–8378); S154 / Chapter 103 / `BY Statement` (PDF p. 8378); S154 / Chapter 103 / `ID Statement` (PDF pp. 8385–8386); S154 / Chapter 103 / `WEIGHT Statement` (PDF p. 8393).
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

data a (drop=i);
do i=1 to 1000;
x1=rannor(1234);
x2=rannor(1234);
e=rannor(1234);
if i > 950 then y=100 + 10*e;
else y=10 + 5*x1 + 3*x2 + 0.5 * e;
output;
end;
run;
data _oracle_input; set a; do _oracle_by=1 to 2; output; end; run;
proc sort data=_oracle_input; by _oracle_by; run;
proc quantreg data=_oracle_input;
by _oracle_by;
model y = x1 x2 / seed=314159;
run;
proc quantreg algorithm=interior(tolerance=1e-6)
ci=none data=a;
model y = x1 x2 / itprint nosummary seed=314159;
run;
proc quantreg algorithm=smooth(rratio=.5) ci=none data=a;
model y = x1 x2 / itprint nosummary seed=314159;
run;

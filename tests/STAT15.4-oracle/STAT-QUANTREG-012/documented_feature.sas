/* STAT-QUANTREG-012: QUANTREG — PERFORMANCE / Computational Resources
 * Source: S154 / Chapter 103 / `PERFORMANCE Statement` (PDF pp. 8391–8392); S154 / Chapter 103 / `Computational Resources` (PDF p. 8415).
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
proc quantreg data=a;
model y = x1 x2 / seed=314159;
run;
proc quantreg algorithm=interior(tolerance=1e-6)
ci=none data=a;
model y = x1 x2 / itprint nosummary seed=314159;
run;
proc quantreg algorithm=smooth(rratio=.5) ci=none data=a;
model y = x1 x2 / itprint nosummary seed=314159;
run;

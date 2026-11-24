/* STAT-NLMIXED-013: NLMIXED — Displayed Output / ODS Table Names
 * Source: S154 / Chapter 89 / `Displayed Output` (PDF pp. 7163–7165); S154 / Chapter 89 / `ODS Table Names` (PDF pp. 7165–7166).
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

ods trace on;
%let na = 100;
%let nb = 5;
%let nr = 2;
data nested;
do A = 1 to &na;
err1 = 3*rannor(339205);
do B = 1 to &nb;
err2 = 2*rannor(314159);
do rep = 1 to &nr;
err3 = 1*rannor(314159);
resp = 10 + err1 + err2 + err3;
output;
end;
end;
end;
run;
proc nlmixed data = nested;
bounds vara >=0, varb_a >=0;
mean = intercept + aeffect + beffect;
model resp ~ normal (mean, s2);
random aeffect ~ normal(0,vara) subject = A;
random beffect ~ normal(0,varb_a) subject = B(A);
run;
ods trace off;

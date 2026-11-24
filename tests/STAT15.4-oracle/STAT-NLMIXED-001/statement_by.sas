/* STAT-NLMIXED-001: NLMIXED — Data input, variable roles, and basic options
 * Source: S154 / Chapter 89 / `PROC NLMIXED Statement` (PDF pp. 7097–7116); S154 / Chapter 89 / `BY Statement` (PDF p. 7117); S154 / Chapter 89 / `ID Statement` (PDF p. 7122).
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
data _oracle_input; set nested; do _oracle_by=1 to 2; output; end; run;
proc sort data=_oracle_input; by _oracle_by; run;
proc nlmixed data = _oracle_input;
by _oracle_by;
bounds vara >=0, varb_a >=0;
mean = intercept + aeffect + beffect;
model resp ~ normal (mean, s2);
random aeffect ~ normal(0,vara) subject = A;
random beffect ~ normal(0,varb_a) subject = B(A);
run;

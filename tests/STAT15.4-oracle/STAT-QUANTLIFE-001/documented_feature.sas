/* STAT-QUANTLIFE-001: QUANTLIFE — Data input, variable roles, and basic options
 * Source: S154 / Chapter 102 / `PROC QUANTLIFE Statement` (PDF pp. 8332–8335); S154 / Chapter 102 / `BY Statement` (PDF pp. 8335–8336); S154 / Chapter 102 / `WEIGHT Statement` (PDF p. 8339).
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

data survival;
call streaminit(518);
do id=1 to 80;
drug=mod(id,2);
age=25+mod(id*7,40);
time=exp(2+0.25*drug+0.008*age+rand('normal')*0.4);
status=(mod(id,5) ne 0);
output;
end;
run;
proc quantlife data=survival seed=1268;
class drug;
model time*status(0)=drug age / quantile=0.5;
run;

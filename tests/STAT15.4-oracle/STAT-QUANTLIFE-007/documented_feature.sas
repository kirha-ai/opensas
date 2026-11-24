/* STAT-QUANTLIFE-007: QUANTLIFE — OUTPUT / Output Data Sets
 * Source: S154 / Chapter 102 / `OUTPUT Statement` (PDF p. 8338); S154 / Chapter 102 / `Output Data Sets` (PDF pp. 8343–8344).
 * Discriminates: Verified default procedure context; explicit statements: OUTPUT
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

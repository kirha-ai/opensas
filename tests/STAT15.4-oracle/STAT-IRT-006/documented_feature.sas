/* STAT-IRT-006: IRT — Notation for the Item Response Theory Model / Assumptions / PROC IRT Contrasted with Other SAS Procedures
 * Source: S154 / Chapter 72 / `Notation for the Item Response Theory Model` (PDF pp. 5340–5342); S154 / Chapter 72 / `Assumptions` (PDF p. 5342); S154 / Chapter 72 / `PROC IRT Contrasted with Other SAS Procedures` (PDF pp. 5342–5343).
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

data responses;
call streaminit(329);
array item[5] item1-item5;
do subject=1 to 150;
theta=rand('normal');
do k=1 to 5;
item[k]=rand('bernoulli',1/(1+exp(-(theta-(k-3)/2))));
end;
output;
end;
keep item1-item5;
run;
proc irt data=responses;
var item1-item5;
run;

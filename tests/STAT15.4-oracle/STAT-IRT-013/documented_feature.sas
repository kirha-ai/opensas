/* STAT-IRT-013: IRT — ODS Graphics
 * Source: S154 / Chapter 72 / `ODS Graphics` (PDF pp. 5354–5355).
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

ods graphics on;
ods trace on;
ods trace on;
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
ods trace off;
ods trace off;
ods graphics off;

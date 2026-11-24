/* STAT-RMSTREG-012: RMSTREG — ODS Graphics
 * Source: S154 / Chapter 106 / `ODS Graphics` (PDF pp. 8759–8760).
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
data survival;
call streaminit(218);
do id=1 to 100;
age=25+mod(id*7,40);
x=mod(id,2);
time=exp(0.5+0.15*x+0.01*age+rand('normal')*0.7);
status=(mod(id,4) ne 0);
output;
end;
run;
proc rmstreg data=survival tau=5;
model time*status(0)=age x / link=linear method=pv;
run;
ods trace off;
ods trace off;
ods graphics off;

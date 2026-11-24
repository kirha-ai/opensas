/* STAT-HPQUANTSELECT-001: HPQUANTSELECT — Data input, variable roles, and basic options
 * Source: S154 / Chapter 66 / `PROC HPQUANTSELECT Statement` (PDF pp. 4985–4987); S154 / Chapter 66 / `BY Statement` (PDF p. 4987); S154 / Chapter 66 / `ID Statement` (PDF pp. 4988–4989); S154 / Chapter 66 / `WEIGHT Statement` (PDF p. 4995).
 * Discriminates: Seeded synthetic quantile-regression fixture: Data input, variable roles, and basic options
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data sample;
call streaminit(314159);
do id=1 to 120;
 x=rand('normal'); z=rand('normal'); w=rand('normal'); group=1+mod(id,3);
 y=2+1.5*x-0.6*z+0.4*group+rand('normal');
 role=mod(id,4); output;
end;
run;
data sample; set sample; _weight=1+mod(id,2); run;
proc hpquantselect data=sample;
class group;
model y=x z w group / quantile=0.5 clb;
id id;
weight _weight;
performance nthreads=1;
run;

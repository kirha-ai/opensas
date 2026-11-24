/* STAT-HPQUANTSELECT-011: HPQUANTSELECT — OUTPUT / Output Data Set
 * Source: S154 / Chapter 66 / `OUTPUT Statement` (PDF pp. 4991–4993); S154 / Chapter 66 / `Output Data Set` (PDF pp. 5007–5008).
 * Discriminates: Seeded synthetic quantile-regression fixture: OUTPUT / Output Data Set
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

proc hpquantselect data=sample;
class group;
model y=x z w group / quantile=0.5 clb;
id id;
output out=predicted p=pred r=resid stdp=se lclm=lo uclm=hi;
performance nthreads=1;
run;
proc print data=predicted(obs=10); run;

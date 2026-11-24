/* STAT-HPQUANTSELECT-004: HPQUANTSELECT — Linear Model with iid Errors / Linear-in-Parameter Model with Non-iid Settings / More Statistics for Parameter Estimates
 * Source: S154 / Chapter 66 / `Linear Model with iid Errors` (PDF pp. 4996–4997); S154 / Chapter 66 / `Linear-in-Parameter Model with Non-iid Settings` (PDF pp. 4997–4998); S154 / Chapter 66 / `More Statistics for Parameter Estimates` (PDF p. 4998).
 * Discriminates: Seeded synthetic quantile-regression fixture: Linear Model with iid Errors / Linear-in-Parameter Model with Non-iid Settings / More Statistics for Parameter Estimates
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
model y=x z w group / quantile=0.5 clb sparsity(iid);

performance nthreads=1;
run;

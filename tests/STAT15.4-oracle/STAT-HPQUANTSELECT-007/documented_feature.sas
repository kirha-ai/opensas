/* STAT-HPQUANTSELECT-007: HPQUANTSELECT — Using the Validation ACL as the SELECT= Criterion / Computational Method
 * Source: S154 / Chapter 66 / `Using the Validation ACL as the SELECT= Criterion` (PDF p. 5006); S154 / Chapter 66 / `Computational Method` (PDF pp. 5006–5007).
 * Discriminates: Seeded synthetic quantile-regression fixture: Using the Validation ACL as the SELECT= Criterion / Computational Method
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
partition rolevar=role(validate="0");
selection method=forward(select=validate choose=validate);
performance nthreads=1;
run;

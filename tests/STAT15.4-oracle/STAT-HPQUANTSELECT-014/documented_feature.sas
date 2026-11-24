/* STAT-HPQUANTSELECT-014: HPQUANTSELECT — Official examples and feature integration regression
 * Source: S154 / Chapter 66 / `Examples: HPQUANTSELECT Procedure` (PDF pp. 5012–5018).
 * Discriminates: Seeded synthetic quantile-regression fixture: Official examples and feature integration regression
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
model y=x z w group / quantile=0.25 0.75 clb;
selection method=backward(select=sbc choose=sbc);
performance nthreads=1;
run;

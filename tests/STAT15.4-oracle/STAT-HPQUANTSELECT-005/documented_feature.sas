/* STAT-HPQUANTSELECT-005: HPQUANTSELECT — Quasi-likelihood Information Criteria / Statistical Tests for Significance Level / Classification Variables and the SPLIT Option
 * Source: S154 / Chapter 66 / `Quasi-likelihood Information Criteria` (PDF pp. 4999–5000); S154 / Chapter 66 / `Statistical Tests for Significance Level` (PDF pp. 5000–5002); S154 / Chapter 66 / `Classification Variables and the SPLIT Option` (PDF pp. 5002–5003).
 * Discriminates: Seeded synthetic quantile-regression fixture: Quasi-likelihood Information Criteria / Statistical Tests for Significance Level / Classification Variables and the SPLIT Option
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
class group(split);
model y=x z w group / quantile=0.5 clb;
selection method=forward(select=sbc choose=sbc);
performance nthreads=1;
run;

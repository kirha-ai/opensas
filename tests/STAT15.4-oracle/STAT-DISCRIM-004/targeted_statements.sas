/* STAT-DISCRIM-004: DISCRIM — PRIORS / Posterior Probability Error-Rate Estimates
 * Source: S154 / Chapter 42 / `PRIORS Statement` (PDF pp. 2662–2663); S154 / Chapter 42 / `Posterior Probability Error-Rate Estimates` (PDF pp. 2672–2674).
 * Discriminates: Explicit PRIORS statement behavior on seeded synthetic inputs.
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
do id=1 to 90;
 x=rand('normal'); z=rand('normal'); w=rand('normal');
 group=1+mod(id,3); block=1+mod(id,5);
 y=5+1.5*x-0.6*z+0.4*group+rand('normal');
 y2=2+0.5*x+0.8*z+rand('normal'); output;
end;
run;
proc discrim data=sample; class group; var x y; priors equal; run; proc discrim data=sample; class group; var x y; priors proportional; run;

/* STAT-FACTOR-003: FACTOR — PARTIAL / Variable Weights and Variance Explained / Simplicity Functions for Rotations
 * Source: S154 / Chapter 44 / `PARTIAL Statement` (PDF p. 2817); S154 / Chapter 44 / `Variable Weights and Variance Explained` (PDF pp. 2829–2830); S154 / Chapter 44 / `Simplicity Functions for Rotations` (PDF pp. 2830–2831).
 * Discriminates: Explicit PARTIAL statement behavior on seeded synthetic inputs.
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
proc factor data=sample nfactors=1; var x y y2; partial z; run;

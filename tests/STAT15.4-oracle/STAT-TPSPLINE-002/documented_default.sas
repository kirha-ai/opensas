/* STAT-TPSPLINE-002: TPSPLINE — Thin-plate smoothing spline estimation
 * Source: S154 / Chapter 125 / `Getting Started: TPSPLINE Procedure` (PDF pp. 10288–10297); S154 / Chapter 125 / `Overview: TPSPLINE Procedure` (PDF pp. 10286–10288).
 * Discriminates: Thin-plate smoothing, smoothing parameter search and output predictions/limits
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data surface; do x1=-1 to 1 by 0.5; do x2=-1 to 1 by 0.5; do rep=1 to 2; y=3+x1-2*x2+0.5*x1*x2+0.1*cos(rep+x1+x2); output; end; end; end; run;
proc tpspline data=surface; model y=(x1 x2) / lognlambda=(-4 to -2.5 by 0.5); output out=predicted pred uclm lclm; run;
proc print data=predicted(obs=12) noobs; run;

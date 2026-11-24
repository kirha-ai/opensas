/* STAT-HPFMM-002: HPFMM — High-performance finite mixture model estimation
 * Source: S154 / Chapter 58 / `Getting Started: HPFMM Procedure` (PDF pp. 4508–4532); S154 / Chapter 58 / `Overview: HPFMM Procedure` (PDF pp. 4504–4508).
 * Discriminates: Documented default analysis with explicit complete public or synthetic inputs
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data yeast;
input count f;
n = 5;
datalines;
0 213
1 128
2 37
3 18
4 3
5 1
;
proc hpfmm data=yeast seed=314159;
model count/n = / k=2;
freq f;
run;
quit;

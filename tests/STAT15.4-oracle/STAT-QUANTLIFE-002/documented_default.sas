/* STAT-QUANTLIFE-002: QUANTLIFE — Quantile regression for survival data
 * Source: S154 / Chapter 102 / `Getting Started: QUANTLIFE Procedure` (PDF pp. 8328–8331); S154 / Chapter 102 / `Overview: QUANTLIFE Procedure` (PDF pp. 8326–8328).
 * Discriminates: Small synthetic/public-input default model adapted to the documented Getting Started procedure
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data survival; call streaminit(518); do id=1 to 80; drug=mod(id,2); age=25+mod(id*7,40); time=exp(2+0.25*drug+0.008*age+rand('normal')*0.4); status=(mod(id,5) ne 0); output; end; run;
proc quantlife data=survival seed=1268; class drug; model time*status(0)=drug age / quantile=0.5; run;

/* STAT-FACTOR-010: FACTOR — PATHDIAGRAM / ODS Graphics
 * Source: S154 / Chapter 44 / `PATHDIAGRAM Statement` (PDF pp. 2817–2823); S154 / Chapter 44 / `ODS Graphics` (PDF pp. 2842–2843).
 * Discriminates: Example 44.2: Principal Factor Analysis
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

ods graphics on;
ods trace on;
ods trace on;
data SocioEconomics;
input Population School Employment Services HouseValue;
datalines;
5700 12.8 2500 270 25000
1000 10.9 600 10 10000
3400 8.8 1000 10 9000
3800 13.6 1700 140 25000
4000 12.8 1600 140 25000
8200 8.3 2600 60 12000
1200 11.4 400 10 16000
9100 11.5 3300 60 14000
9900 12.5 3400 180 18000
9600 13.7 3600 390 25000
9600 9.6 3300 80 12000
9400 11.4 4000 100 13000
;
run;
ods graphics on;
proc factor data=SocioEconomics
priors=smc msa residual
rotate=promax reorder
outstat=fact_all
plots=(scree initloadings preloadings loadings);
run;
ods graphics off;
proc print data=fact_all;
run;
data fact2(type=factor);
set fact_all;
if _TYPE_ in('PATTERN' 'FCORR') then delete;
if _TYPE_='UNROTATE' then _TYPE_='PATTERN';
run;
proc factor data=fact2 rotate=quartimax reorder;
run;
ods graphics on;
proc factor data=fact2 rotate=hk norm=weight reorder plots=loadings;
run;
ods graphics off;
run;
quit;
ods trace off;
ods trace off;
ods graphics off;

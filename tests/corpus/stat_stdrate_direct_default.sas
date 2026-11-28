/* STAT-STDRATE-001: STDRATE — Data input, variable roles, and basic options
 * Source: S154 / Chapter 116 / `PROC STDRATE Statement` (PDF pp. 9493–9497); S154 / Chapter 116 / `BY Statement` (PDF p. 9497); S154 / Chapter 116 / `POPULATION Statement` (PDF pp. 9497–9499); S154 / Chapter 116 / `STRATA Statement` (PDF pp. 9500–9502).
 * Discriminates: Verified default procedure context; explicit statements: POPULATION, STRATA
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data study;
input age $ event total;
datalines;
young 10 1000
old 30 1500
;
data reference;
input age $ total;
datalines;
young 20000
old 10000
;
run;
proc stdrate data=study refdata=reference method=direct stat=rate;
population event=event total=total;
reference total=total;
strata age;
run;

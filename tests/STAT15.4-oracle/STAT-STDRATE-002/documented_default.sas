/* STAT-STDRATE-002: STDRATE — Rate and risk standardization and comparison
 * Source: S154 / Chapter 116 / `Getting Started: STDRATE Procedure` (PDF pp. 9486–9493); S154 / Chapter 116 / `Overview: STDRATE Procedure` (PDF pp. 9484–9486).
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

data study; input age $ event total; datalines;
young 10 1000
old 30 1500
;
data reference; input age $ total; datalines;
young 20000
old 10000
;
run;
proc stdrate data=study refdata=reference method=direct stat=rate; population event=event total=total; reference total=total; strata age; run;

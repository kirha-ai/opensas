/* STAT-APP-001: Power and Sample Size Application product scope and launch contract
 * Source: S154 / Chapter 97 / `The Power and Sample Size Application` (PDF pp. 7989–7990).
 * Discriminates: Installed SAS/STAT product availability and the POWER computation behind the application
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

proc product_status; run;
proc power; onesamplemeans mean=8 stddev=40 ntotal=150 power=.; run;

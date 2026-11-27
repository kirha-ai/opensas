/* expect-rc: 1; D-009: SAS status 2 is a user-program error. */
/* STAT-TTEST-005: TTEST — One-Sample Design
 * Source: S154 / Chapter 128 / `One-Sample Design` (PDF pp. 10620–10623).
 * Discriminates: Documented invalid ALPHA boundary
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data time; input time @@; datalines;
43 90 84 87 116 95 86 99 93 92
121 71 66 98 79 102 60 112 105 98
;
run;
proc ttest data=time alpha=1; var time; run;

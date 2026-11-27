/* STAT-COMMON-005: Shared interfaces for tests, tail probabilities, and confidence intervals
 * Source: S154 / Chapter 4 / `Hypothesis Testing and Power` (PDF p. 58); S154 / Chapter 5 / `Testing Linear Hypotheses` (PDF p. 112); S154 / Chapter 5 / `Parameter Estimates and Associated Statistics` (PDF pp. 106–110).
 * Discriminates: Two-sided and directed one-sided probabilities and intervals
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
proc ttest data=time h0=80 sides=2; var time; run;
proc ttest data=time h0=80 sides=u; var time; run;
proc ttest data=time h0=80 sides=l; var time; run;

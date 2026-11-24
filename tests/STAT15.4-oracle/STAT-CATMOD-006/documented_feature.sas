/* STAT-CATMOD-006: CATMOD — Logistic Analysis / Log-Linear Model Analysis / Computational Method
 * Source: S154 / Chapter 36 / `Logistic Analysis` (PDF pp. 2227–2229); S154 / Chapter 36 / `Log-Linear Model Analysis` (PDF pp. 2229–2232); S154 / Chapter 36 / `Computational Method` (PDF pp. 2247–2248).
 * Discriminates: Example 36.4: Log-Linear Model, Three Dependent Variables
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data bartlett;
input Length Time Status wt @@;
datalines;
1 1 1 156 1 1 2 84 1 2 1 84 1 2 2 156
2 1 1 107 2 1 2 133 2 2 1 31 2 2 2 209
;
title 'Bartlett''s Data';
proc catmod data=bartlett;
weight wt;
model Length*Time*Status=_response_
/ noparm pred=freq;
loglin Length|Time|Status @ 2;
title2 'Model with No 3-Variable Interaction';
quit;

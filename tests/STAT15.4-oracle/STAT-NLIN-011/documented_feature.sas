/* STAT-NLIN-011: NLIN — Measures of Nonlinearity, Diagnostics and Inference
 * Source: S154 / Chapter 88 / `Measures of Nonlinearity, Diagnostics and Inference` (PDF pp. 7016–7024).
 * Discriminates: Example 88.6: ODS Graphics and Diagnostics
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data contrived;
input x1 x2 y;
datalines;
-4.0 -2.5 -10.0
-3.0 -2.0 -5.0
-2.0 -1.5 -2.0
-1.0 -1.0 -1.0
0.0 0.0 1.5
1.0 1.0 4.0
2.0 1.5 5.0
3.0 2.0 6.0
4.0 2.5 7.0
-3.5 -2.2 -7.1
-3.5 -1.7 -5.1
3.5 0.7 6.1
2.5 1.2 7.5
;
ods graphics on;
proc nlin data=contrived bias hougaard
NLINMEASURES plots(stats=all)=(diagnostics);
parms alpha=2.0
gamma=0.0;
model y = alpha*x1 + exp(gamma*x2);
run;
ods graphics off;
run;
quit;

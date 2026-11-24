/* STAT-NLIN-006: NLIN — Computational Methods / Covariance Matrix of Parameter Estimates / Convergence Measures
 * Source: S154 / Chapter 88 / `Computational Methods` (PDF pp. 7028–7033); S154 / Chapter 88 / `Covariance Matrix of Parameter Estimates` (PDF pp. 7035–7036); S154 / Chapter 88 / `Convergence Measures` (PDF pp. 7036–7037).
 * Discriminates: Getting Started: NLIN Procedure
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data Enzyme;
input Concentration Velocity @@;
datalines;
0.26 124.7 0.30 126.9
0.48 135.9 0.50 137.6
0.54 139.6 0.68 141.1
0.82 142.8 1.14 147.6
1.28 149.8 1.38 149.4
1.80 153.9 2.30 152.5
2.44 154.5 2.48 154.7
;
proc nlin data=Enzyme method=marquardt hougaard;
parms theta1=155
theta2=0 to 0.07 by 0.01;
model Velocity = theta1*Concentration / (theta2 + Concentration);
run;

/* STAT-NLIN-009: NLIN — BOOTSTRAP
 * Source: S154 / Chapter 88 / `BOOTSTRAP Statement` (PDF pp. 6998–7000).
 * Discriminates: Example 88.7: Parameter Profiling and Bootstrapping; explicit statements: BOOTSTRAP
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data clarke1987a;
input x y;
datalines;
1 3.183
2 3.059
3 2.871
4 2.622
5 2.541
6 2.184
7 2.110
8 2.075
9 2.018
10 1.903
11 1.770
12 1.762
13 1.550
;
ods graphics on;
proc nlin data=clarke1987a plots(stats=none)=diagnostics;
parms theta1=-0.15
theta2=2.0
theta3=0.80;
profile theta1 theta3 / range = -6 to 2 by 0.2 all;
bootstrap / nsamples=999 seed=123 bootplots bootci bootcov;
model y = theta3 + theta2*exp(theta1*x);
run;
ods graphics off;
run;
quit;

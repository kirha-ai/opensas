/* STAT-HPNLMOD-002: HPNLMOD — High-performance nonlinear model objectives and estimation
 * Source: S154 / Chapter 63 / `Getting Started: HPNLMOD Procedure` (PDF pp. 4873–4875); S154 / Chapter 63 / `Overview: HPNLMOD Procedure` (PDF pp. 4872–4873).
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

data enzyme; input conc rate @@; datalines;
0.26 124.7 0.30 126.9 0.48 135.9 0.50 137.6 0.54 139.6 0.68 141.1 0.82 142.8 1.14 147.6 1.28 149.8 1.38 149.4 1.80 153.9 2.30 152.5 2.44 154.5 2.48 154.7
;
run;
proc hpnlmod data=enzyme; parms theta1=160 theta2=0.1; model rate ~ residual(theta1*conc/(theta2+conc)); run;

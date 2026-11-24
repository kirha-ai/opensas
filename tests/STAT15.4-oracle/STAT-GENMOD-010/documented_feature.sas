/* STAT-GENMOD-010: GENMOD — EXACT / EXACTOPTIONS / Exact Logistic and Exact Poisson Regression
 * Source: S154 / Chapter 51 / `EXACT Statement` (PDF pp. 3535–3538); S154 / Chapter 51 / `EXACTOPTIONS Statement` (PDF pp. 3538–3541); S154 / Chapter 51 / `Exact Logistic and Exact Poisson Regression` (PDF pp. 3612–3615).
 * Discriminates: Example 51.11: Exact Poisson Regression; explicit statements: EXACT, EXACTOPTIONS
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data ingots;
input Heat Soak Notready Total @@;
lnTotal= log(Total);
datalines;
7 1.0 0 10 14 1.0 0 31 27 1.0 1 56 51 1.0 3 13
7 1.7 0 17 14 1.7 0 43 27 1.7 4 44 51 1.7 0 1
7 2.2 0 7 14 2.2 2 33 27 2.2 0 21 51 2.2 0 1
7 2.8 0 12 14 2.8 0 31 27 2.8 1 22 51 4.0 0 1
7 4.0 0 9 14 4.0 0 19 27 4.0 1 16
;
proc genmod data=ingots;
class Heat Soak / param=ref;
model Notready=Heat Soak / offset=lnTotal dist=Poisson link=log;
exact Heat Soak / joint estimate;
exactoptions statustime=10;
run;

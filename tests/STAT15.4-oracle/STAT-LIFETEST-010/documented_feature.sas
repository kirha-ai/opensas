/* STAT-LIFETEST-010: LIFETEST — Plot Options Superseded by ODS Graphics / ODS Graphics / Modifying the Survival Plots
 * Source: S154 / Chapter 77 / `Plot Options Superseded by ODS Graphics` (PDF pp. 5705–5710); S154 / Chapter 77 / `ODS Graphics` (PDF pp. 5712–5714); S154 / Chapter 77 / `Modifying the Survival Plots` (PDF pp. 5714–5715).
 * Discriminates: Example 77.2: Enhanced Survival Plot and Multiple-Comparison Adjustments
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

ods graphics on;
ods trace on;
ods trace on;
proc print data=Sashelp.BMT(obs=10);
run;
ods graphics on;
proc lifetest data=sashelp.BMT plots=survival(atrisk=0 to 2500 by 500);
time T * Status(0);
strata Group / test=logrank adjust=sidak;
run;
proc lifetest data=sashelp.BMT notable plots=none;
time T * Status(0);
strata Group / test=logrank adjust=sidak diff=control('AML-Low Risk');
run;
proc format;
invalue $bmtifmt 'ALL' = 1 'AML-Low Risk' = 2 'AML-High Risk' = 3;
value bmtfmt 1 = 'ALL' 2 = 'AML-Low Risk' 3 = 'AML-High Risk';
run;
data Bmt2;
set sashelp.BMT(rename=(Group=G));
Group = input(input(G, $bmtifmt.), 1.);
label Group = 'Disease Group';
format Group bmtfmt.;
run;
proc LIFETEST data=Bmt2 plots=s(atrisk(outside maxlen=13)=0 to 2500 by 500);
time T*Status(0);
strata Group / order=internal;
run;
proc lifetest data=Bmt2 plots=survival(cl cb=hw strata=panel);
time T * Status(0);
strata Group/order=internal;
run;
ods graphics off;
run;
quit;
ods trace off;
ods trace off;
ods graphics off;

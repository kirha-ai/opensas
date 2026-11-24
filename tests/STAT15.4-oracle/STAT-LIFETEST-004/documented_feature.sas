/* STAT-LIFETEST-004: LIFETEST — Kernel-Smoothed Hazard Estimate / Comparison of Two or More Groups of Survival Data / Rank Tests for the Association of Survival Time with Covariates
 * Source: S154 / Chapter 77 / `Kernel-Smoothed Hazard Estimate` (PDF pp. 5679–5681); S154 / Chapter 77 / `Comparison of Two or More Groups of Survival Data` (PDF pp. 5681–5686); S154 / Chapter 77 / `Rank Tests for the Association of Survival Time with Covariates` (PDF pp. 5686–5687).
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

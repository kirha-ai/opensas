/* STAT-REG-005: REG — Computations for Ridge Regression and IPC Analysis
 * Source: S154 / Chapter 105 / `Computations for Ridge Regression and IPC Analysis` (PDF pp. 8648–8649).
 * Discriminates: Example 105.5: Ridge Regression for Acetylene Data
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data acetyl;
input x1-x4 @@;
x1x2 = x1 * x2;
x1x1 = x1 * x1;
label x1 = 'reactor temperature(celsius)'
x2 = 'h2 to n-heptone ratio'
x3 = 'contact time(sec)'
x4 = 'conversion percentage'
x1x2= 'temperature-ratio interaction'
x1x1= 'squared temperature';
datalines;
1300 7.5 .012 49 1300 9 .012 50.2 1300 11 .0115 50.5
1300 13.5 .013 48.5 1300 17 .0135 47.5 1300 23 .012 44.5
1200 5.3 .04 28 1200 7.5 .038 31.5 1200 11 .032 34.5
1200 13.5 .026 35 1200 17 .034 38 1200 23 .041 38.5
1100 5.3 .084 15 1100 7.5 .098 17 1100 11 .092 20.5
1100 17 .086 29.5
;
ods graphics on;
proc reg data=acetyl outvif
outest=b ridge=0 to 0.02 by .002;
model x4=x1 x2 x3 x1x2 x1x1;
run;
proc print data=b;
run;
proc reg data=acetyl plots(only)=ridge(unpack VIFaxis=log)
outest=b ridge=0 to 0.02 by .002;
model x4=x1 x2 x3 x1x2 x1x1;
run;
ods graphics off;
run;
quit;

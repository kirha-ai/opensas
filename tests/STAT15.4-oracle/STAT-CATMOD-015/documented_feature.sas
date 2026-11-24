/* STAT-CATMOD-015: CATMOD — Official examples and feature integration regression
 * Source: S154 / Chapter 36 / `Examples: CATMOD Procedure` (PDF pp. 2257–2299).
 * Discriminates: Example 36.3: Logistic Regression, Standard Response Function
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
input Heat Soak nready ntotal @@;
Count=nready;
Y=1;
output;
Count=ntotal-nready;
Y=0;
output;
drop nready ntotal;
datalines;
7 1.0 0 10 14 1.0 0 31 27 1.0 1 56 51 1.0 3 13
7 1.7 0 17 14 1.7 0 43 27 1.7 4 44 51 1.7 0 1
7 2.2 0 7 14 2.2 2 33 27 2.2 0 21 51 2.2 0 1
7 2.8 0 12 14 2.8 0 31 27 2.8 1 22 51 4.0 0 1
7 4.0 0 9 14 4.0 0 19 27 4.0 1 16
;
title 'Maximum Likelihood Logistic Regression';
proc catmod data=ingots;
weight Count;
direct Heat Soak;
model Y=Heat Soak / freq covb corrb itprint design;
quit;

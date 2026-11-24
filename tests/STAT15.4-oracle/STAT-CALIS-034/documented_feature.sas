/* STAT-CALIS-034: CALIS — Official examples and feature integration regression
 * Source: S154 / Chapter 33 / `Examples: CALIS Procedure` (PDF pp. 1838–2111).
 * Discriminates: Example 33.6: Linear Regression Model
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data sales;
input q1 q2 q3 q4;
datalines;
1.03 1.54 1.11 2.22
1.23 1.43 1.65 2.12
3.24 2.21 2.31 5.15
1.23 2.35 2.21 7.17
.98 2.13 1.76 2.38
1.02 2.05 3.15 4.28
1.54 1.99 1.77 2.00
1.76 1.79 2.28 3.18
1.11 3.41 2.20 3.21
1.32 2.32 4.32 4.78
1.22 1.81 1.51 3.15
1.11 2.15 2.45 6.17
1.01 2.12 1.96 2.08
1.34 1.74 2.16 3.28
;

run;

proc calis data=sales;
path q1 ===> q4;
run;
proc reg data=sales;
model q4 = q1;
run;
proc calis data=sales meanstr;
path q1 ===> q4;
run;

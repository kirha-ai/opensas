/* STAT-SURVEYMEANS-017: SURVEYMEANS — Official examples and feature integration regression
 * Source: S154 / Chapter 121 / `Examples: SURVEYMEANS Procedure` (PDF pp. 9984–9999).
 * Discriminates: Example 121.4: Analyzing Survey Data with Missing Values
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data IceCream;
input Grade Spending @@;
if Grade=7 then Prob=20/1824;
if Grade=8 then Prob=9/1025;
if Grade=9 then Prob=11/1151;
Weight=1/Prob;
datalines;
7 7 7 7 8 . 9 10 7 . 7 10 7 3 8 20 8 19 7 2
7 . 9 15 8 16 7 6 7 6 7 6 9 15 8 17 8 14 9 .
9 8 9 7 7 3 7 12 7 4 9 14 8 18 9 9 7 2 7 1
7 4 7 11 9 8 8 . 8 13 7 . 9 . 9 11 7 2 7 9
;
data StudentTotals;
input Grade _total_;
datalines;
7 1824
8 1025
9 1151
;
title 'Analysis of Ice Cream Spending';
proc surveymeans data=IceCream total=StudentTotals nomcar mean sum;
strata Grade;
var Spending;
weight Weight;
run;

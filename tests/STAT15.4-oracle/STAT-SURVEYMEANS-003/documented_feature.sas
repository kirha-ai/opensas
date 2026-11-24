/* STAT-SURVEYMEANS-003: SURVEYMEANS — DOMAIN / POSTSTRATA / RATIO
 * Source: S154 / Chapter 121 / `DOMAIN Statement` (PDF pp. 9925–9927); S154 / Chapter 121 / `POSTSTRATA Statement` (PDF pp. 9927–9929); S154 / Chapter 121 / `RATIO Statement` (PDF pp. 9929–9931).
 * Discriminates: Example 121.6: Comparing Domain Means; explicit statements: DOMAIN
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data IceCreamDataDomain;
input Grade Spending Gender$ @@;
datalines;
7 7 M 7 7 F 8 12 F
9 10 M 7 1 M 7 10 M
7 3 M 8 20 F 8 19 M
7 2 M 7 2 F 9 15 F
8 16 F 7 6 F 7 6 M
7 6 M 9 15 M 8 17 F
8 14 M 9 8 M 9 8 F
9 7 F 7 3 F 7 12 M
7 4 M 9 14 F 8 18 M
9 9 F 7 2 F 7 1 M
7 4 M 7 11 M 9 8 M
8 10 M 8 13 F 7 2 F
9 6 F 9 11 M 7 2 F
7 9 F
;
data IceCreamDataDomain;
set IceCreamDataDomain;
if Grade=7 then Prob=20/1824;
if Grade=8 then Prob=9/1025;
if Grade=9 then Prob=11/1151;
Weight=1/Prob;
run;
data StudentTotals;
input Grade _TOTAL_;
datalines;
7 1824
8 1025
9 1151
;
ods graphics on;
proc surveymeans data=IceCreamDataDomain total=StudentTotals;
strata Grade;
var spending;
domain Grade / diffmeans adjust=bon;
domain Gender*Grade('8') / diffmeans;
weight Weight;
run;
run;
quit;

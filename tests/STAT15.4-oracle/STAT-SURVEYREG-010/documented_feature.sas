/* STAT-SURVEYREG-010: SURVEYREG — Contrasts / Domain Analysis
 * Source: S154 / Chapter 123 / `Contrasts` (PDF pp. 10156–10157); S154 / Chapter 123 / `Domain Analysis` (PDF p. 10157).
 * Discriminates: Example 123.8: Comparing Domain Statistics
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
input Grade Spending Income Gender$ @@;
datalines;
7 7 39 M 7 7 38 F 8 12 47 F
9 10 47 M 7 1 34 M 7 10 43 M
7 3 44 M 8 20 60 F 8 19 57 M
7 2 35 M 7 2 36 F 9 15 51 F
8 16 53 F 7 6 37 F 7 6 41 M
7 6 39 M 9 15 50 M 8 17 57 F
8 14 46 M 9 8 41 M 9 8 41 F
9 7 47 F 7 3 39 F 7 12 50 M
7 4 43 M 9 14 46 F 8 18 58 M
9 9 44 F 7 2 37 F 7 1 37 M
7 4 44 M 7 11 42 M 9 8 41 M
8 10 42 M 8 13 46 F 7 2 40 F
9 6 45 F 9 11 45 M 7 2 36 F
7 9 46 F
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
proc surveymeans data=IceCreamDataDomain total=StudentTotals;
strata Grade;
var spending;
domain Gender;
weight Weight;
run;
title1 'Ice Cream Spending Analysis';
title2 'Compare Domain Statistics';
proc surveyreg data=IceCreamDataDomain total=StudentTotals;
strata Grade;
class Gender;
model Spending = Gender / vadjust=none;
lsmeans Gender / diff;
weight Weight;
run;
ods graphics on;
title1 'Ice Cream Spending Analysis';
title2 'Compare Domain Statistics';
proc surveyreg data=IceCreamDataDomain total=StudentTotals;
strata Grade;
class Grade;
model Spending = Grade / vadjust=none;
lsmeans Grade / diff plots=(diff meanplot(cl));
weight Weight;
run;

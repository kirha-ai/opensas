/* STAT-SURVEYMEANS-002: SURVEYMEANS — Mean, total, and proportion estimation for complex surveys
 * Source: S154 / Chapter 121 / `Getting Started: SURVEYMEANS Procedure` (PDF pp. 9900–9907); S154 / Chapter 121 / `Overview: SURVEYMEANS Procedure` (PDF p. 9900).
 * Discriminates: Getting Started: SURVEYMEANS Procedure
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
if (Spending < 10) then Group='less';
else Group='more';
datalines;
7 7 7 7 8 12 9 10 7 1 7 10 7 3 8 20 8 19 7 2
7 2 9 15 8 16 7 6 7 6 7 6 9 15 8 17 8 14 9 8
9 8 9 7 7 3 7 12 7 4 9 14 8 18 9 9 7 2 7 1
7 4 7 11 9 8 8 10 8 13 7 2 9 6 9 11 7 2 7 9
;
ods graphics on;
title1 'Analysis of Ice Cream Spending';
title2 'Simple Random Sample Design';
proc surveymeans data=IceCream total=4000;
var Spending Group;
run;
data StudentTotals;
input Grade _total_;
datalines;
7 1824
8 1025
9 1151
;
data IceCream;
set IceCream;
if Grade=7 then Prob=20/1824;
if Grade=8 then Prob=9/1025;
if Grade=9 then Prob=11/1151;
Weight=1/Prob;
run;
title1 'Analysis of Ice Cream Spending';
title2 'Stratified Sample Design';
proc surveymeans data=IceCream total=StudentTotals;
stratum Grade / list;
var Spending Group;
weight Weight;
run;
title1 'Analysis of Ice Cream Spending';
title2 'Stratified Sample Design';
proc surveymeans data=IceCream total=StudentTotals;
stratum Grade / list;
var Spending Group;
weight Weight;
ods output Statistics=MyStat;
run;
ods output Statistics=MyStat;
proc print data=MyStat;
run;

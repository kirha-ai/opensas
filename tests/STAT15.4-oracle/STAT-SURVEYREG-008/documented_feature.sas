/* STAT-SURVEYREG-008: SURVEYREG — Taylor Series (Linearization) / Balanced Repeated Replication (BRR) Method / Fay's BRR Method
 * Source: S154 / Chapter 123 / `Taylor Series (Linearization)` (PDF pp. 10148–10149); S154 / Chapter 123 / `Balanced Repeated Replication (BRR) Method` (PDF pp. 10151–10152); S154 / Chapter 123 / `Fay's BRR Method` (PDF pp. 10152–10153).
 * Discriminates: Getting Started: SURVEYREG Procedure
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
input Grade Spending Income Kids @@;
datalines;
7 7 39 2 7 7 38 1 8 12 47 1
9 10 47 4 7 1 34 4 7 10 43 2
7 3 44 4 8 20 60 3 8 19 57 4
7 2 35 2 7 2 36 1 9 15 51 1
8 16 53 1 7 6 37 4 7 6 41 2
7 6 39 2 9 15 50 4 8 17 57 3
8 14 46 2 9 8 41 2 9 8 41 1
9 7 47 3 7 3 39 3 7 12 50 2
7 4 43 4 9 14 46 3 8 18 58 4
9 9 44 3 7 2 37 1 7 1 37 2
7 4 44 2 7 11 42 2 9 8 41 2
8 10 42 2 8 13 46 1 7 2 40 3
9 6 45 1 9 11 45 4 7 2 36 1
7 9 46 1
;
title1 'Ice Cream Spending Analysis';
title2 'Simple Random Sample Design';
proc surveyreg data=IceCream total=4000;
class Kids;
model Spending = Income Kids / solution;
run;
data StudentTotals;
input Grade _TOTAL_;
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
ods graphics on;
title1 'Ice Cream Spending Analysis';
title2 'Stratified Sample Design';
proc surveyreg data=IceCream total=StudentTotals;
strata Grade /list;
model Spending = Income;
weight Weight;
run;
title1 'Ice Cream Spending Analysis';
title2 'Stratified Sample Design';
proc surveyreg data=IceCream total=StudentTotals;
strata Grade /list;
model Spending = Income;
weight Weight;
ods output ParameterEstimates = MyParmEst;
run;
ods output ParameterEstimates = MyParmEst;
proc print data=MyParmEst;
run;

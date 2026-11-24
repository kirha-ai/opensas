/* STAT-SURVEYREG-012: SURVEYREG — CONTRAST / ESTIMATE / TEST
 * Source: S154 / Chapter 123 / `CONTRAST Statement` (PDF pp. 10127–10128); S154 / Chapter 123 / `ESTIMATE Statement` (PDF pp. 10130–10131); S154 / Chapter 123 / `TEST Statement` (PDF pp. 10140–10141).
 * Discriminates: Example 123.9: Variance Estimate Using the Jackknife Method; explicit statements: ESTIMATE
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
run;
data IceCream; set IceCream; if Grade=7 then Weight=1824/20; if Grade=8 then Weight=1025/9; if Grade=9 then Weight=1151/11; run;
title1 'Ice Cream Spending Analysis';
title2 'Use the Jackknife Method to Estimate the Variance';
proc surveyreg data=IceCream
varmethod=JACKKNIFE(outweights=JKWeights);
strata Grade;
class Kids;
model Spending = Income Kids / solution;
weight Weight;
run;

/* STAT-LIFEREG-004: LIFEREG — PROBPLOT / Model Specification / Computational Method
 * Source: S154 / Chapter 76 / `PROBPLOT Statement` (PDF pp. 5561–5565); S154 / Chapter 76 / `Model Specification` (PDF pp. 5566–5567); S154 / Chapter 76 / `Computational Method` (PDF pp. 5567–5569).
 * Discriminates: Example 76.6: Probability Plotting—Arbitrary Censoring; explicit statements: PROBPLOT
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data Micro;
input t1 t2 f;
datalines;
. 6 6
6 12 2
12 24 0
24 48 2
24 . 1
48 168 1
48 . 839
168 500 1
168 . 150
500 1000 2
500 . 149
1000 2000 1
1000 . 147
2000 . 122
;
ods graphics on;
proc lifereg data=Micro;
model ( t1 t2 ) = / d=lognormal intercept=25 scale=5;
weight f;
probplot
pupper = 10
itprintem
printprobs
maxitem = (1000,25)
ppout;
inset;
run;

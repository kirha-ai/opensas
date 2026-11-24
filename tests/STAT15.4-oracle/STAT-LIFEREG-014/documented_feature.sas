/* STAT-LIFEREG-014: LIFEREG — INSET / Probability Plotting / Plot Options Superseded by ODS Graphics / ODS Graphics
 * Source: S154 / Chapter 76 / `INSET Statement` (PDF pp. 5550–5551); S154 / Chapter 76 / `Probability Plotting` (PDF pp. 5576–5581); S154 / Chapter 76 / `Plot Options Superseded by ODS Graphics` (PDF pp. 5590–5599); S154 / Chapter 76 / `ODS Graphics` (PDF pp. 5601–5602).
 * Discriminates: Example 76.6: Probability Plotting—Arbitrary Censoring; explicit statements: INSET
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

ods graphics on;
ods trace on;
ods trace on;
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
ods trace off;
ods trace off;
ods graphics off;

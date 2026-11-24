/* STAT-GAM-004: GAM — Nonparametric Regression / Additive Models and Generalized Additive Models / Forms of Additive Models
 * Source: S154 / Chapter 48 / `Nonparametric Regression` (PDF pp. 3307–3308); S154 / Chapter 48 / `Additive Models and Generalized Additive Models` (PDF pp. 3308–3309); S154 / Chapter 48 / `Forms of Additive Models` (PDF pp. 3309–3310).
 * Discriminates: Example 48.1: Generalized Additive Model with Binary Data
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

title 'Comparing PROC GAM with PROC GENMOD';
data kyphosis;
input Age StartVert NumVert Kyphosis @@;
datalines;
71 5 3 0 158 14 3 0 128 5 4 1
2 1 5 0 1 15 4 0 1 16 2 0
61 17 2 0 37 16 3 0 113 16 2 0
59 12 6 1 82 14 5 1 148 16 3 0
18 2 5 0 1 12 4 0 243 8 8 0
168 18 3 0 1 16 3 0 78 15 6 0
175 13 5 0 80 16 5 0 27 9 4 0
22 16 2 0 105 5 6 1 96 12 3 1
131 3 2 0 15 2 7 1 9 13 5 0
12 2 14 1 8 6 3 0 100 14 3 0
4 16 3 0 151 16 2 0 31 16 3 0
125 11 2 0 130 13 5 0 112 16 3 0
140 11 5 0 93 16 3 0 1 9 3 0
52 6 5 1 20 9 6 0 91 12 5 1
73 1 5 1 35 13 3 0 143 3 9 0
61 1 4 0 97 16 3 0 139 10 3 1
136 15 4 0 131 13 5 0 121 3 3 1
177 14 2 0 68 10 5 0 9 17 2 0
139 6 10 1 2 17 2 0 140 15 4 0
72 15 5 0 2 13 3 0 120 8 5 1
51 9 7 0 102 13 3 0 130 1 4 1
114 8 7 1 81 1 4 0 118 16 3 0
118 16 4 0 17 10 4 0 195 17 2 0
159 13 4 0 18 11 4 0 15 16 5 0
158 15 4 0 127 12 4 0 87 16 4 0
206 10 4 0 11 15 3 0 178 15 4 0
157 13 3 1 26 13 7 0 120 13 2 0
42 6 7 1 36 13 4 0
;
proc genmod data=kyphosis descending;
model Kyphosis = Age StartVert NumVert/link=logit dist=binomial;
run;
title 'Comparing PROC GAM with PROC GENMOD';
proc gam data=kyphosis;
model Kyphosis (event='1') = spline(Age ,df=3)
spline(StartVert,df=3)
spline(NumVert ,df=3) / dist=binomial;
run;
title 'PROC GAM with Approximate Analysis of Deviance';
proc gam data=kyphosis;
model Kyphosis (event='1') = spline(Age ,df=3)
spline(StartVert,df=3)
spline(NumVert ,df=3) /
dist=binomial anodev=norefit;
run;
ods graphics on;
proc gam data=kyphosis plots=components(clm commonaxes);
model Kyphosis (event='1') = spline(Age ,df=3)
spline(StartVert,df=3)
spline(NumVert ,df=3) / dist=binomial;
run;
ods graphics off;
title 'Comparing PROC GAM with PROC GENMOD';
proc genmod data=kyphosis descending;
model kyphosis = Age Age *Age
StartVert StartVert*StartVert
NumVert NumVert *NumVert /
link=logit dist=binomial;
run;

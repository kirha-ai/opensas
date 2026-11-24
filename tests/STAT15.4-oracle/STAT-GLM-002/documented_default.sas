/* STAT-GLM-002: GLM — General linear model estimation and basic effect tests
 * Source: S154 / Chapter 53 / `Getting Started: GLM Procedure` (PDF pp. 4047–4055); S154 / Chapter 53 / `Overview: GLM Procedure` (PDF pp. 4045–4047).
 * Discriminates: Getting Started: GLM Procedure
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

title 'Analysis of Unbalanced 2-by-2 Factorial';
data exp;
input A $ B $ Y @@;
datalines;
A1 B1 12 A1 B1 14 A1 B2 11 A1 B2 9
A2 B1 20 A2 B1 18 A2 B2 17
;
proc glm data=exp;
class A B;
model Y=A B A*B;
run;
ods graphics on;
proc glm data=exp;
class A B;
model Y=A B A*B;
run;
ods graphics off;
title 'Regression in PROC GLM';
data iron;
input fe loss @@;
datalines;
0.01 127.6 0.48 124.0 0.71 110.8 0.95 103.9
1.19 101.5 0.01 130.1 0.48 122.0 1.44 92.3
0.71 113.1 1.96 83.7 0.01 128.0 1.44 91.4
1.96 86.2
;
proc sgscatter data=iron;
plot loss*fe;
run;
ods graphics off;
proc glm data=iron;
model loss=fe fe*fe;
run;
ods graphics on;
proc glm data=iron;
model loss=fe fe*fe;
run;
ods graphics off;
proc glm data=iron;
model loss=fe;
run;

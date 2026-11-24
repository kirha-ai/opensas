/* STAT-GENMOD-003: GENMOD — CLASS / MODEL / ZEROMODEL
 * Source: S154 / Chapter 51 / `CLASS Statement` (PDF pp. 3526–3529); S154 / Chapter 51 / `MODEL Statement` (PDF pp. 3544–3555); S154 / Chapter 51 / `ZEROMODEL Statement` (PDF pp. 3567–3568).
 * Discriminates: Example 51.1: Logistic Regression; explicit statements: CLASS, MODEL
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data drug;
input drug$ x r n @@;
datalines;
A .1 1 10 A .23 2 12 A .67 1 9
B .2 3 13 B .3 4 15 B .45 5 16 B .78 5 13
C .04 0 10 C .15 0 11 C .56 1 12 C .7 2 12
D .34 5 10 D .6 5 9 D .7 8 10
E .2 12 20 E .34 15 20 E .56 13 15 E .8 17 20
;
proc genmod data=drug;
class drug;
model r/n = x drug / dist = bin
link = logit
lrci;
run;

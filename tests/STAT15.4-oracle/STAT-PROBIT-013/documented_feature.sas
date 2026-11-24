/* STAT-PROBIT-013: PROBIT — Official examples and feature integration regression
 * Source: S154 / Chapter 100 / `Examples: PROBIT Procedure` (PDF pp. 8171–8198).
 * Discriminates: Example 100.3: Logistic Regression and Scoring New Data
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data news;
input sex $ age subs @@;
datalines;
Female 35 0 Male 44 0
Male 45 1 Female 47 1
Female 51 0 Female 47 0
Male 54 1 Male 47 1
Female 35 0 Female 34 0
Female 48 0 Female 56 1
Male 46 1 Female 59 1
Female 46 1 Male 59 1
Male 38 1 Female 39 0
Male 49 1 Male 42 1
Male 50 1 Female 45 0
Female 47 0 Female 30 1
Female 39 0 Female 51 0
Female 45 0 Female 43 1
Male 39 1 Male 31 0
Female 39 0 Male 34 0
Female 52 1 Female 46 0
Male 58 1 Female 50 1
Female 32 0 Female 52 1
Female 35 0 Female 51 0
;
proc format;
value subscrib 1 = 'accept' 0 = 'reject';
run;
proc probit data=news;
class sex;
model subs(event="accept")=sex age / d=logistic itprint;
format subs subscrib.;
store out=LogitModel;
run;

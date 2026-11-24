/* STAT-LOGISTIC-011: LOGISTIC — EXACT / EXACTOPTIONS / Exact Conditional Logistic Regression
 * Source: S154 / Chapter 79 / `EXACT Statement` (PDF pp. 5861–5863); S154 / Chapter 79 / `EXACTOPTIONS Statement` (PDF pp. 5863–5867); S154 / Chapter 79 / `Exact Conditional Logistic Regression` (PDF pp. 5949–5954).
 * Discriminates: Example 79.11: Conditional Logistic Regression for Matched Pairs Data; explicit statements: EXACT
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data Data1;
do ID=1 to 63;
do Outcome = 1 to 0 by -1;
input Gall Hyper @@;
output;
end;
end;
datalines;
0 0 0 0 0 0 0 0 0 1 0 1 0 0 1 0 1 0 0 1
0 1 0 0 1 0 0 0 1 1 0 1 0 0 0 0 0 0 0 0
1 0 0 0 0 0 0 1 1 0 0 1 1 0 1 0 1 0 0 1
0 1 0 0 0 0 1 1 0 0 1 1 0 0 0 1 0 1 0 0
0 0 1 1 0 1 0 1 0 1 0 0 0 0 0 0 0 0 0 0
0 0 0 1 1 0 0 1 0 0 0 1 1 0 0 0 0 1 0 0
0 1 0 0 0 1 0 0 0 1 0 0 0 0 0 0 1 1 1 1
0 0 0 1 0 1 0 0 0 1 0 1 0 1 0 1 0 1 0 0
0 0 0 0 0 1 1 0 0 0 0 1 0 0 0 0 1 0 0 0
0 0 0 0 1 1 0 0 0 1 0 0 0 0 0 0 0 1 0 1
0 0 0 0 0 1 0 1 0 1 0 0 0 1 0 0 1 0 0 0
0 0 0 0 1 1 1 0 0 0 0 0 0 0 0 0 1 1 0 0
1 0 1 0 0 1 0 0 1 0 0 0
;
proc logistic data=Data1;
strata ID;
model outcome(event='1')=Gall;
run;
proc logistic data=Data1 exactonly;
strata ID;
model outcome(event='1')=Gall;
exact Gall / estimate=both;
run;

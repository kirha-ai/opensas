/* STAT-LOGISTIC-002: LOGISTIC — Logistic model estimation for categorical responses
 * Source: S154 / Chapter 79 / `Getting Started: LOGISTIC Procedure` (PDF pp. 5828–5835); S154 / Chapter 79 / `Overview: LOGISTIC Procedure` (PDF pp. 5825–5828); S154 / Chapter 9 / `Introduction to Categorical Data Analysis Procedures` (PDF pp. 187–198).
 * Discriminates: Getting Started: LOGISTIC Procedure
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data ingots;
input Heat Soak r n @@;
datalines;
7 1.0 0 10 14 1.0 0 31 27 1.0 1 56 51 1.0 3 13
7 1.7 0 17 14 1.7 0 43 27 1.7 4 44 51 1.7 0 1
7 2.2 0 7 14 2.2 2 33 27 2.2 0 21 51 2.2 0 1
7 2.8 0 12 14 2.8 0 31 27 2.8 1 22 51 4.0 0 1
7 4.0 0 9 14 4.0 0 19 27 4.0 1 16
;
ods graphics on;
proc logistic data=ingots;
model r/n = Heat | Soak;
oddsratio Heat / at(Soak=1 2 3 4);
run;
proc logistic data=ingots;
model r/n = Heat Soak;
run;
data ingots;
input Heat Soak NotReady Freq @@;
datalines;
7 1.0 0 10 14 1.0 0 31 14 4.0 0 19 27 2.2 0 21 51 1.0 1 3
7 1.7 0 17 14 1.7 0 43 27 1.0 1 1 27 2.8 1 1 51 1.0 0 10
7 2.2 0 7 14 2.2 1 2 27 1.0 0 55 27 2.8 0 21 51 1.7 0 1
7 2.8 0 12 14 2.2 0 31 27 1.7 1 4 27 4.0 1 1 51 2.2 0 1
7 4.0 0 9 14 2.8 0 31 27 1.7 0 40 27 4.0 0 15 51 4.0 0 1
;
proc logistic data=ingots;
model NotReady(event='1') = Heat Soak;
freq Freq;
run;

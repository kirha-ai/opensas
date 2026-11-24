/* STAT-MI-016: MI — Official examples and feature integration regression
 * Source: S154 / Chapter 82 / `Examples: MI Procedure` (PDF pp. 6500–6551).
 * Discriminates: Example 82.3: Monotone Regression Method
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data Fish1;
title 'Fish Measurement Data';
input Length1 Length2 Length3 @@;
datalines;
23.2 25.4 30.0 24.0 26.3 31.2 23.9 26.5 31.1
26.3 29.0 33.5 26.5 29.0 . 26.8 29.7 34.7
26.8 . . 27.6 30.0 35.0 27.6 30.0 35.1
28.5 30.7 36.2 28.4 31.0 36.2 28.7 . .
29.1 31.5 . 29.5 32.0 37.3 29.4 32.0 37.2
29.4 32.0 37.2 30.4 33.0 38.3 30.4 33.0 38.5
30.9 33.5 38.6 31.0 33.5 38.7 31.3 34.0 39.5
31.4 34.0 39.2 31.5 34.5 . 31.8 35.0 40.6
31.9 35.0 40.5 31.8 35.0 40.9 32.0 35.0 40.6
32.7 36.0 41.5 32.8 36.0 41.6 33.5 37.0 42.6
35.0 38.5 44.1 35.0 38.5 44.0 36.2 39.5 45.3
37.4 41.0 45.9 38.0 41.0 46.5
;
run;
proc mi data=Fish1 round=.1 mu0= 0 35 45
seed=13951639 nimpute=8 out=outex3;
monotone reg(Length2/ details)
regpmm(Length3= Length1 Length2 Length1*Length2/ details);
var Length1 Length2 Length3;
run;
proc print data=outex3(obs=10);
title 'First 10 Observations of the Imputed Data Set';
run;

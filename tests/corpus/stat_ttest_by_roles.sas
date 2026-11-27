/* STAT-TTEST-001: TTEST — Data input, variable roles, and basic options
 * Source: S154 / Chapter 128 / `PROC TTEST Statement` (PDF pp. 10604–10613); S154 / Chapter 128 / `BY Statement` (PDF pp. 10615–10616); S154 / Chapter 128 / `CLASS Statement` (PDF p. 10616); S154 / Chapter 128 / `FREQ Statement` (PDF pp. 10616–10617); S154 / Chapter 128 / `VAR Statement` (PDF pp. 10617–10618); S154 / Chapter 128 / `WEIGHT Statement` (PDF p. 10618); S154 / Chapter 128 / `Input Data Set of Statistics` (PDF pp. 10618–10619); S154 / Chapter 128 / `Missing Values` (PDF p. 10619).
 * Discriminates: BY boundaries, multiple VAR roles, frequency versus analysis weights, and explicit input data
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data sample;
 input x y group $ freq weight;
 datalines;
43 40 A 1 1
90 84 A 2 1
84 88 A 1 2
87 80 A 1 1
116 110 A 1 1
95 91 A 1 2
86 79 B 1 1
99 101 B 2 1
93 90 B 1 2
92 85 B 1 1
121 115 B 1 1
71 72 B 1 2
;
run;
proc sort data=sample; by group; run;
proc ttest data=sample order=data; by group; var x y; freq freq; weight weight; run;

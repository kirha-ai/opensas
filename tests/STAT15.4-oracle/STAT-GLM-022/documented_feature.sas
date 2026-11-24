/* STAT-GLM-022: GLM — Official examples and feature integration regression
 * Source: S154 / Chapter 53 / `Examples: GLM Procedure` (PDF pp. 4172–4224).
 * Discriminates: Example 53.2: Regression with Mileage Data
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

title 'Gasoline Mileage Experiment';
data mileage;
input mph mpg @@;
datalines;
20 15.4
30 20.2
40 25.7
50 26.2 50 26.6 50 27.4
55 .
60 24.8
;
ods graphics on;
proc glm;
model mpg=mph mph*mph / p clm;
run;
ods graphics off;
run;
quit;

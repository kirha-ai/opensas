/* STAT-REG-020: REG — Official examples and feature integration regression
 * Source: S154 / Chapter 105 / `Examples: REG Procedure` (PDF pp. 8676–8725).
 * Discriminates: Example 105.4: Regression with Quantitative and Qualitative Variables
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

title 'Regression with Quantitative and Qualitative Variables';
data insurance;
input time size type @@;
sizetype=size*type;
datalines;
17 151 0 26 92 0 21 175 0 30 31 0 22 104 0 0 277 0 12 210 0
19 120 0 4 290 0 16 238 0 28 164 1 15 272 1 11 295 1 38 68 1
31 85 1 21 224 1 20 166 1 13 305 1 30 124 1 14 246 1
;
proc reg data=insurance;
model time = size type sizetype;
run;
delete sizetype;
print;
run;
output out=out r=r p=p;
run;
proc sgplot data=out;
scatter x=p y=r / markerchar=type group=type;
run;
proc sgplot data=out;
scatter x=size y=p / markerchar=type group=type;
run;

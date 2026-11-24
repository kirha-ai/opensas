/* STAT-REG-016: REG — OUTPUT / Output Data Sets
 * Source: S154 / Chapter 105 / `OUTPUT Statement` (PDF pp. 8590–8592); S154 / Chapter 105 / `Output Data Sets` (PDF pp. 8603–8610).
 * Discriminates: Example 105.4: Regression with Quantitative and Qualitative Variables; explicit statements: OUTPUT
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

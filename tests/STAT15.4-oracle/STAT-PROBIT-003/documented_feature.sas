/* STAT-PROBIT-003: PROBIT — CLASS / MODEL / Response Level Ordering
 * Source: S154 / Chapter 100 / `CLASS Statement` (PDF pp. 8106–8108); S154 / Chapter 100 / `MODEL Statement` (PDF pp. 8112–8118); S154 / Chapter 100 / `Response Level Ordering` (PDF pp. 8120–8122).
 * Discriminates: Example 100.2: Multilevel Response; explicit statements: CLASS, MODEL
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data multi;
input Prep $ Dose Symptoms $ N;
LDose=log10(Dose);
if Prep='test' then PrepDose=LDose;
else PrepDose=0;
datalines;
stand 10 None 33
stand 10 Mild 7
stand 10 Severe 10
stand 20 None 17
stand 20 Mild 13
stand 20 Severe 17
stand 30 None 14
stand 30 Mild 3
stand 30 Severe 28
stand 40 None 9
stand 40 Mild 8
stand 40 Severe 32
test 10 None 44
test 10 Mild 6
test 10 Severe 0
test 20 None 32
test 20 Mild 10
test 20 Severe 12
test 30 None 23
test 30 Mild 7
test 30 Severe 21
test 40 None 16
test 40 Mild 6
test 40 Severe 19
;
proc probit data=multi;
class Prep;
nonpara: model Symptoms(order=data)=Prep LDose PrepDose / lackfit;
weight N;
run;
proc probit data=multi;
class Prep;
parallel: model Symptoms(order=data)=Prep LDose / lackfit;
weight N;
run;
proc probit data=multi
plots=(predpplot(level=("None" "Mild" "Severe"))
cdfplot(level=("None" "Mild" "Severe")));
class Prep;
parallel: model Symptoms(order=data)=Prep LDose / lackfit;
weight N;
run;
data xrow;
input Prep $ Dose Symptoms $ N;
LDose=log10(Dose);
datalines;
stand 40 Severe 32
run;
proc probit data=multi xdata=xrow
plots=(predpplot(level=("None" "Mild" "Severe"))
cdfplot(level=("None" "Mild" "Severe")));
class Prep;
parallel: model Symptoms(order=data)=Prep LDose / lackfit;
weight N;
run;

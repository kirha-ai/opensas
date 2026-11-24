/* STAT-SURVEYLOGISTIC-007: SURVEYLOGISTIC — INEST= Data Set / Specification of Population Totals and Sampling Rates / Primary Sampling Units (PSUs)
 * Source: S154 / Chapter 120 / `INEST= Data Set` (PDF p. 9850); S154 / Chapter 120 / `Specification of Population Totals and Sampling Rates` (PDF pp. 9850–9851); S154 / Chapter 120 / `Primary Sampling Units (PSUs)` (PDF p. 9851).
 * Discriminates: Example 120.1: Stratified Sampling
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

proc format; value Class 1='Freshman' 2='Sophomore' 3='Junior' 4='Senior'; run;
data Enrollment;
format Class Class.;
input Class _TOTAL_;
datalines;
1 3734
2 3565
3 3903
4 4196
;
proc format;
value Design 1='A' 2='B' 3='C';
value Rating
1='dislike very much'
2='dislike'
3='neutral'
4='like'
5='like very much';
run;
data WebSurvey;
format Class Class. Design Design. Rating Rating.;
do Class=1 to 4;
do Design=1 to 3;
do Rating=1 to 5;
input Count @@;
output;
end;
end;
end;
datalines;
10 34 35 16 15 8 21 23 26 22 5 10 24 30 21
1 14 25 23 37 11 14 20 34 21 16 19 30 23 12
19 12 26 18 25 11 14 24 33 18 10 18 32 23 17
8 15 35 30 12 15 22 34 9 20 2 34 30 18 16
;
data WebSurvey;
set WebSurvey;
if Class=1 then Weight=3734/300;
if Class=2 then Weight=3565/300;
if Class=3 then Weight=3903/300;
if Class=4 then Weight=4196/300;
run;
proc surveylogistic data=WebSurvey total=Enrollment;
stratum Class;
freq Count;
class Design;
model Rating (order=internal) = design;
weight Weight;
run;
proc surveylogistic data=WebSurvey total=Enrollment;
stratum Class;
freq Count;
class Design;
model Rating (ref='neutral') = Design /link=glogit;
weight Weight;
run;

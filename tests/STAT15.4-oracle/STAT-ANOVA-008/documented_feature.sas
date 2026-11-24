/* STAT-ANOVA-008: ANOVA — Output Data Set
 * Source: S154 / Chapter 29 / `Output Data Set` (PDF pp. 1139–1140).
 * Discriminates: Getting Started: ANOVA Procedure
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

title1 'Nitrogen Content of Red Clover Plants';
data Clover;
input Strain $ Nitrogen @@;
datalines;
3DOK1 19.4 3DOK1 32.6 3DOK1 27.0 3DOK1 32.1 3DOK1 33.0
3DOK5 17.7 3DOK5 24.8 3DOK5 27.9 3DOK5 25.2 3DOK5 24.3
3DOK4 17.0 3DOK4 19.4 3DOK4 9.1 3DOK4 11.9 3DOK4 15.8
3DOK7 20.7 3DOK7 21.0 3DOK7 20.5 3DOK7 18.8 3DOK7 18.6
3DOK13 14.3 3DOK13 14.4 3DOK13 11.8 3DOK13 11.6 3DOK13 14.2
COMPOS 17.3 COMPOS 19.4 COMPOS 19.1 COMPOS 16.9 COMPOS 20.8
;
ods graphics on;
proc anova data = Clover;
class Strain;
model Nitrogen = Strain;
means Strain / tukey;
run;
title1 'Randomized Complete Block';
data RCB;
input Block Treatment $ Yield Worth @@;
datalines;
1 A 32.6 112 1 B 36.4 130 1 C 29.5 106
2 A 42.7 139 2 B 47.1 143 2 C 32.9 112
3 A 35.3 124 3 B 40.1 134 3 C 33.6 116
;
proc anova data=RCB;
class Block Treatment;
model Yield Worth=Block Treatment;
run;
means Treatment;
run;

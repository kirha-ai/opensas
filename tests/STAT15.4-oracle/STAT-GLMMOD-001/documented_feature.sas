/* STAT-GLMMOD-001: GLMMOD — Data input, variable roles, and basic options
 * Source: S154 / Chapter 54 / `PROC GLMMOD Statement` (PDF pp. 4236–4238); S154 / Chapter 54 / `BY Statement` (PDF p. 4238); S154 / Chapter 54 / `FREQ and WEIGHT Statements` (PDF p. 4239); S154 / Chapter 54 / `Missing Values` (PDF p. 4240).
 * Discriminates: Verified default procedure context
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

title 'Nitrogen Content of Red Clover Plants';
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
proc glmmod data=Clover;
class Strain;
model Nitrogen = Strain;
run;
proc glmmod data=Clover outdesign=CloverDesign noprint;
class Strain;
model Nitrogen = Strain;
run;
proc reg data=CloverDesign;
model Nitrogen = Col2-Col7;
run;

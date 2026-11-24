/* STAT-GLMPOWER-009: GLMPOWER — Error and Information Output / Displayed Output / ODS Table Names
 * Source: S154 / Chapter 55 / `Error and Information Output` (PDF pp. 4282–4283); S154 / Chapter 55 / `Displayed Output` (PDF pp. 4283–4284); S154 / Chapter 55 / `ODS Table Names` (PDF pp. 4284–4285).
 * Discriminates: Getting Started: GLMPOWER Procedure
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

ods trace on;
data Exemplary;
do Variety = 1 to 2;
do Exposure = 1 to 3;
input Height @@;
output;
end;
end;
datalines;
14 16 21
10 15 16
;
proc glmpower data=Exemplary;
class Variety Exposure;
model Height = Variety | Exposure;
power
stddev = 5
ntotal = 60
power = .;
run;
ods graphics on;
proc glmpower data=Exemplary;
class Variety Exposure;
model Height = Variety | Exposure;
power
stddev = 4 6.5
ntotal = 60
power = .;
plot x=n min=30 max=90;
run;
ods graphics off;
data Exemplary;
input Variety $ Exposure $ HeightOrig HeightNew Weight;
datalines;
1 1 14 15 1
1 2 16 16 2
1 3 21 20 2
2 1 10 11 1
2 2 15 14 2
2 3 16 15 2
;
proc glmpower data=Exemplary;
class Variety Exposure;
model HeightOrig HeightNew = Variety | Exposure;
weight Weight;
contrast 'Exposure=1 vs Exposure=3' Exposure 1 0 -1;
power
stddev = 5
ntotal = 60
power = .;
run;
ods trace off;

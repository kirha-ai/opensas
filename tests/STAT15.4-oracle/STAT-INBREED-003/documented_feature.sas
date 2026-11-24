/* STAT-INBREED-003: INBREED — GENDER / MATINGS / DATA= Data Set
 * Source: S154 / Chapter 71 / `GENDER Statement` (PDF p. 5277); S154 / Chapter 71 / `MATINGS Statement` (PDF pp. 5277–5278); S154 / Chapter 71 / `DATA= Data Set` (PDF pp. 5279–5280).
 * Discriminates: Example 71.2: Pedigree Analysis; explicit statements: GENDER, MATINGS
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data Swine;
input Swine_Number $ Sire $ Dam $ Sex $;
datalines;
3504 2200 2501 M
3514 2521 3112 F
3519 2521 2501 F
2501 2200 3112 M
2789 3504 3514 F
3501 2521 3514 M
3712 3504 3514 F
3121 2200 3501 F
;
title 'Least Related Matings';
proc inbreed data=Swine ind average;
var Swine_Number Sire Dam;
matings 2501 / 3501 3504 ,
3712 / 3121;
gender Sex;
run;

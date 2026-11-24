/* STAT-HPMIXED-004: HPMIXED — Model Assumptions / Computing and Maximizing the Likelihood / Sparse Matrix Techniques
 * Source: S154 / Chapter 62 / `Model Assumptions` (PDF pp. 4843–4844); S154 / Chapter 62 / `Computing and Maximizing the Likelihood` (PDF pp. 4844–4845); S154 / Chapter 62 / `Sparse Matrix Techniques` (PDF pp. 4846–4847).
 * Discriminates: Example 62.2: Comparing Results from PROC HPMIXED and PROC MIXED
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data heights;
input Family Gender$ Height @@;
datalines;
1 F 67 1 F 66 1 F 64 1 M 71 1 M 72 2 F 63
2 F 63 2 F 67 2 M 69 2 M 68 2 M 70 3 F 63
3 M 64 4 F 67 4 F 66 4 M 67 4 M 67 4 M 69
;
proc mixed;
class Family Gender;
model Height = Gender / s;
random Family Family*Gender / s;
run;
proc hpmixed;
class Family Gender;
model Height = Gender / s;
random Family Family*Gender / s;
test gender;
run;

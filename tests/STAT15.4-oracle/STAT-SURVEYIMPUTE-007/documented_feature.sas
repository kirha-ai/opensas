/* STAT-SURVEYIMPUTE-007: SURVEYIMPUTE — OUTPUT / Output Data Sets
 * Source: S154 / Chapter 119 / `OUTPUT Statement` (PDF pp. 9716–9718); S154 / Chapter 119 / `Output Data Sets` (PDF p. 9763).
 * Discriminates: Getting Started: SURVEYIMPUTE Procedure; explicit statements: OUTPUT
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data SIS_Survey_Sub;
input State $ NewUser School SamplingWeight Department Response @@;
datalines;
GA 1 1 25 1 1 GA 1 1 25 1 2 GA 1 1 25 1 2 GA 1 1 15 . . GA 1 1 15 0 3
GA 1 2 25 . 3 GA 1 2 25 1 1 GA 1 2 25 . 1 GA 1 2 15 0 . GA 1 2 15 0 1
GA 1 3 25 1 . GA 1 3 25 1 4 GA 1 3 25 1 4 GA 1 3 15 . 5 GA 1 3 15 0 .
GA 1 4 25 0 3 GA 1 4 25 0 4 GA 1 4 25 0 . GA 1 4 15 1 3 GA 1 4 15 1 5
GA 1 5 25 0 3 GA 1 5 25 0 2 GA 1 5 25 0 2 GA 1 5 15 1 4 GA 1 5 15 1 .
GA 1 6 25 0 4 GA 1 6 25 0 . GA 1 6 25 0 3 GA 1 6 15 1 . GA 1 6 15 1 4
GA 1 7 25 0 . GA 1 7 25 0 . GA 1 7 25 0 3 GA 1 7 15 0 5 GA 1 7 15 0 1
GA 1 8 25 1 2 GA 1 8 25 1 4 GA 1 8 25 1 4 GA 1 8 15 0 4 GA 1 8 15 0 .
GA 1 9 25 1 4 GA 1 9 25 1 . GA 1 9 25 1 . GA 1 9 15 0 5 GA 1 9 15 . 5
GA 1 10 25 0 4 GA 1 10 25 0 4 GA 1 10 25 0 4 GA 1 10 15 0 4 GA 1 10 15 0 3
GA 0 11 25 . 5 GA 0 11 25 1 2 GA 0 11 25 1 . GA 0 11 15 . 3 GA 0 11 15 1 3
GA 0 12 25 1 4 GA 0 12 25 1 2 GA 0 12 25 1 2 GA 0 12 15 1 5 GA 0 12 15 1 .
GA 0 13 25 1 3 GA 0 13 25 1 1 GA 0 13 25 1 1 GA 0 13 15 0 1 GA 0 13 15 0 4
GA 0 14 25 1 . GA 0 14 25 1 3 GA 0 14 25 1 . GA 0 14 15 1 4 GA 0 14 15 1 2
GA 0 15 25 1 . GA 0 15 25 1 5 GA 0 15 25 1 5 GA 0 15 15 1 4 GA 0 15 15 1 .
GA 0 16 25 0 5 GA 0 16 25 0 2 GA 0 16 25 0 2 GA 0 16 15 0 . GA 0 16 15 0 2
GA 0 17 25 0 1 GA 0 17 25 0 1 GA 0 17 25 0 1 GA 0 17 15 0 2 GA 0 17 15 0 3
GA 0 18 25 1 4 GA 0 18 25 1 4 GA 0 18 25 1 4 GA 0 18 15 0 . GA 0 18 15 0 .
GA 0 19 25 0 3 GA 0 19 25 0 5 GA 0 19 25 . 5 GA 0 19 15 0 4 GA 0 19 15 0 5
GA 0 20 25 1 1 GA 0 20 25 1 4 GA 0 20 25 1 4 GA 0 20 15 0 . GA 0 20 15 0 .
GA 0 21 25 1 2 GA 0 21 25 1 2 GA 0 21 25 1 2 GA 0 21 15 0 3 GA 0 21 15 0 3
NC 1 22 30 1 3 NC 1 22 30 . 3 NC 1 22 30 1 3 NC 1 22 20 . 4 NC 1 22 20 1 4
NC 1 23 30 0 3 NC 1 23 30 0 3 NC 1 23 30 0 . NC 1 23 20 0 5 NC 1 23 20 0 .
NC 1 24 30 . 4 NC 1 24 30 0 . NC 1 24 30 . . NC 1 24 20 1 . NC 1 24 20 1 4
NC 1 25 30 0 3 NC 1 25 30 0 3 NC 1 25 30 0 3 NC 1 25 20 1 2 NC 1 25 20 1 2
NC 1 26 30 . 5 NC 1 26 30 1 5 NC 1 26 30 1 5 NC 1 26 20 1 1 NC 1 26 20 1 .
NC 1 27 30 1 . NC 1 27 30 1 1 NC 1 27 30 . 1 NC 1 27 20 0 1 NC 1 27 20 . 1
NC 1 28 30 0 . NC 1 28 30 0 . NC 1 28 30 . 3 NC 1 28 20 1 3 NC 1 28 20 1 .
NC 1 29 30 1 1 NC 1 29 30 . 1 NC 1 29 30 1 . NC 1 29 20 1 5 NC 1 29 20 1 5
NC 1 30 30 0 1 NC 1 30 30 0 1 NC 1 30 30 0 1 NC 1 30 20 1 2 NC 1 30 20 1 2
NC 1 31 30 0 3 NC 1 31 30 0 3 NC 1 31 30 0 3 NC 1 31 20 1 2 NC 1 31 20 1 2
NC 1 32 30 0 5 NC 1 32 30 . . NC 1 32 30 0 5 NC 1 32 20 . 2 NC 1 32 20 0 2
NC 1 33 30 1 3 NC 1 33 30 1 3 NC 1 33 30 1 3 NC 1 33 20 0 1 NC 1 33 20 0 1
NC 1 34 30 0 3 NC 1 34 30 0 . NC 1 34 30 0 . NC 1 34 20 0 . NC 1 34 20 0 5
NC 0 35 35 0 4 NC 0 35 35 0 2 NC 0 35 35 0 2 NC 0 35 20 1 3 NC 0 35 20 1 3
NC 0 36 35 0 2 NC 0 36 35 0 . NC 0 36 35 0 . NC 0 36 20 1 2 NC 0 36 20 . .
NC 0 37 35 1 4 NC 0 37 35 1 1 NC 0 37 35 1 1 NC 0 37 20 1 5 NC 0 37 20 1 5
NC 0 38 35 1 3 NC 0 38 35 . 3 NC 0 38 35 1 3 NC 0 38 20 . 2 NC 0 38 20 0 2
NC 0 39 35 0 3 NC 0 39 35 0 . NC 0 39 35 . . NC 0 39 20 0 . NC 0 39 20 0 3
NC 0 40 35 1 4 NC 0 40 35 1 2 NC 0 40 35 1 2 NC 0 40 20 0 1 NC 0 40 20 0 1
SC 1 41 50 . 2 SC 1 41 50 0 5 SC 1 41 50 0 5 SC 1 41 40 1 . SC 1 41 40 1 .
SC 1 42 50 1 3 SC 1 42 50 1 1 SC 1 42 50 1 1 SC 1 42 40 1 4 SC 1 42 40 1 4
SC 1 43 50 0 . SC 1 43 50 0 . SC 1 43 50 0 . SC 1 43 40 0 . SC 1 43 40 0 .
SC 1 44 50 0 . SC 1 44 50 0 . SC 1 44 50 0 3 SC 1 44 40 1 3 SC 1 44 40 1 .
SC 0 45 55 1 1 SC 0 45 55 1 . SC 0 45 55 1 4 SC 0 45 48 1 4 SC 0 45 48 1 4
SC 0 46 55 1 5 SC 0 46 55 1 3 SC 0 46 55 1 3 SC 0 46 48 . 1 SC 0 46 48 0 1
SC 0 47 55 0 . SC 0 47 55 0 2 SC 0 47 55 0 2 SC 0 47 48 0 2 SC 0 47 48 . 2
;
proc surveyimpute data=SIS_Survey_Sub method=fefi varmethod=jackknife;
class Department Response;
var Department Response;
strata State NewUser;
cluster School;
weight SamplingWeight;
output out=SIS_Survey_Imputed outjkcoefs=SIS_JKCoefs;
run;
proc surveyfreq data=SIS_Survey_Imputed varmethod=jackknife;
table department response department *response;
weight ImpWt;
repweights ImpRepWt: / jkcoefs=SIS_JKCoefs;
run;

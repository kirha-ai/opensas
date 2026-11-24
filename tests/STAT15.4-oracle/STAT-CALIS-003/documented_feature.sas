/* STAT-CALIS-003: CALIS — Classes of Statements in PROC CALIS / Single-Group Analysis Syntax / Multiple-Group Multiple-Model Analysis Syntax / GROUP
 * Source: S154 / Chapter 33 / `Classes of Statements in PROC CALIS` (PDF pp. 1484–1487); S154 / Chapter 33 / `Single-Group Analysis Syntax` (PDF p. 1487); S154 / Chapter 33 / `Multiple-Group Multiple-Model Analysis Syntax` (PDF pp. 1487–1488); S154 / Chapter 33 / `GROUP Statement` (PDF pp. 1565–1568).
 * Discriminates: Example 33.21: Testing Equality of Two Covariance Matrices Using a Multiple-Group Analysis; explicit statements: GROUP
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data expert(type=cov);
length _name_ $32 _type_ $8;
infile datalines truncover;

input _type_ $ _name_ $ high medium low;
datalines;
COV high 5.88 . .
COV medium 2.88 7.16 .
COV low 3.12 4.44 8.14
;
data novice(type=cov);
input _type_ $ _name_ $ high medium low;
datalines;
COV high 6.42 . .
COV medium 1.24 8.25 .
COV low 4.26 2.75 7.99
;
proc calis;
group 1 / data=expert nobs=20 label="Expert";
group 2 / data=novice nobs=18 label="Novice";
model 1 / groups=1,2;
mstruct
var=high medium low;
fitindex NoIndexType On(only)=[chisq df probchi]
chicorrect=eqcovmat;
ods select ModelingInfo MSTRUCTVariables MSTRUCTCovInit Fit;
run;
proc calis covpattern=eqcovmat;
var high medium low;
group 1 / data=expert nobs=20 label="Expert";
group 2 / data=novice nobs=18 label="Novice";
fitindex NoIndexType On(only)=[chisq df probchi];
run;

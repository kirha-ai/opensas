/* STAT-CALIS-023: CALIS — Counting the Degrees of Freedom / FITINDEX / Assessment of Fit
 * Source: S154 / Chapter 33 / `Counting the Degrees of Freedom` (PDF pp. 1774–1776); S154 / Chapter 33 / `FITINDEX Statement` (PDF pp. 1561–1565); S154 / Chapter 33 / `Assessment of Fit` (PDF pp. 1776–1789).
 * Discriminates: Example 33.21: Testing Equality of Two Covariance Matrices Using a Multiple-Group Analysis; explicit statements: FITINDEX
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

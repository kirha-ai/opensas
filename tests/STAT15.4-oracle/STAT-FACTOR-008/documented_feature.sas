/* STAT-FACTOR-008: FACTOR — Output Data Sets
 * Source: S154 / Chapter 44 / `Output Data Sets` (PDF pp. 2826–2828).
 * Discriminates: Example 44.5: Using Confidence Intervals to Locate Salient Factor Loadings
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data test(type=corr);
length _name_ $32 _type_ $8;
infile datalines truncover;

title 'Quartimin-Rotated Factor Solution with Standard Errors';
input _name_ $ test1-test9;
_type_ = 'corr';
datalines;
Test1 1 .561 .602 .290 .404 .328 .367 .179 -.268
Test2 .561 1 .743 .414 .526 .442 .523 .289 -.399
Test3 .602 .743 1 .286 .343 .361 .679 .456 -.532
Test4 .290 .414 .286 1 .677 .446 .412 .400 -.491
Test5 .404 .526 .343 .677 1 .584 .408 .299 -.466
Test6 .328 .442 .361 .446 .584 1 .333 .178 -.306
Test7 .367 .523 .679 .412 .408 .333 1 .711 -.760
Test8 .179 .289 .456 .400 .299 .178 .711 1 -.725
Test9 -.268 -.399 -.532 -.491 -.466 -.306 -.760 -.725 1
;
title2 'A nine-variable-three-factor example';
proc factor data=test method=ml reorder rotate=quartimin
nobs=200 n=3 se cover=.45 alpha=.1;
run;

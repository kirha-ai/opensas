/* STAT-INBREED-007: INBREED — Official examples and feature integration regression
 * Source: S154 / Chapter 71 / `Examples: INBREED Procedure` (PDF pp. 5288–5292).
 * Discriminates: Example 71.1: Monoecious Population Analysis
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data Monoecious;
input Generation Individual Parent1 Parent2 Covariance @@;
datalines;
1 1 . . . 1 2 . . . 1 3 . . .
2 1 1 1 . 2 2 1 2 . 2 3 2 3 .
3 1 1 2 . 3 2 1 3 . 3 3 2 1 .
3 4 1 3 . 3 . 2 3 0.50 3 . 4 3 1.135
;
title 'Inbreeding within Nonoverlapping Generations';
proc inbreed ind covar matrix data=Monoecious;
class Generation;
run;

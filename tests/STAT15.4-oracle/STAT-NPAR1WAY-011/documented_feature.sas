/* STAT-NPAR1WAY-011: NPAR1WAY — Official examples and feature integration regression
 * Source: S154 / Chapter 90 / `Examples: NPAR1WAY Procedure` (PDF pp. 7270–7279).
 * Discriminates: Example 90.5: Exact Savage Multisample Test
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data Mice;
input Treatment $ Days @@;
datalines;
1 1 1 1 1 3 1 3 1 4
2 3 2 4 2 4 2 4 2 15
3 4 3 4 3 10 3 10 3 26
;
proc npar1way savage data=Mice;
class Treatment;
var Days;
exact savage;
run;

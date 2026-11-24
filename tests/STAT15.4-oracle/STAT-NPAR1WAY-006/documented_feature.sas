/* STAT-NPAR1WAY-006: NPAR1WAY — EXACT / Ratio Mean Deviations (RMD) Exact Test / Exact Tests
 * Source: S154 / Chapter 90 / `EXACT Statement` (PDF pp. 7225–7229); S154 / Chapter 90 / `Ratio Mean Deviations (RMD) Exact Test` (PDF pp. 7246–7247); S154 / Chapter 90 / `Exact Tests` (PDF pp. 7249–7253).
 * Discriminates: Example 90.5: Exact Savage Multisample Test; explicit statements: EXACT
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

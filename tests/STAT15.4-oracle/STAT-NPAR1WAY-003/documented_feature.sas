/* STAT-NPAR1WAY-003: NPAR1WAY — Tied Values / Simple Linear Rank Tests for Two-Sample Data / One-Way ANOVA Tests
 * Source: S154 / Chapter 90 / `Tied Values` (PDF p. 7236); S154 / Chapter 90 / `Simple Linear Rank Tests for Two-Sample Data` (PDF pp. 7236–7238); S154 / Chapter 90 / `One-Way ANOVA Tests` (PDF pp. 7238–7239).
 * Discriminates: Example 90.3: Exact Wilcoxon Two-Sample Test
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data React;
input Stim Time @@;
datalines;
1 1.94 1 1.94 1 2.92 1 2.92 1 2.92 1 2.92 1 3.27
1 3.27 1 3.27 1 3.27 1 3.70 1 3.70 1 3.74
2 3.27 2 3.27 2 3.27 2 3.70 2 3.70 2 3.74
;
proc npar1way wilcoxon correct=no data=React;
class Stim;
var Time;
exact wilcoxon;
run;

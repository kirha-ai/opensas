/* STAT-NPAR1WAY-004: NPAR1WAY — Scores for Linear Rank and One-Way ANOVA Tests / Stratified Analysis / Hodges-Lehmann Estimation of Location Shift
 * Source: S154 / Chapter 90 / `Scores for Linear Rank and One-Way ANOVA Tests` (PDF pp. 7239–7241); S154 / Chapter 90 / `Stratified Analysis` (PDF pp. 7241–7242); S154 / Chapter 90 / `Hodges-Lehmann Estimation of Location Shift` (PDF pp. 7242–7244).
 * Discriminates: Example 90.4: Hodges-Lehmann Estimation
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
run;
proc npar1way hl alpha=.02 data=React;
class Stim;
var Time;
exact hl;
ods select WilcoxonScores HodgesLehmann;
run;

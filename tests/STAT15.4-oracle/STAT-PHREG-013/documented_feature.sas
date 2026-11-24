/* STAT-PHREG-013: PHREG — BAYES / Specifics for Bayesian Analysis
 * Source: S154 / Chapter 92 / `BAYES Statement` (PDF pp. 7341–7355); S154 / Chapter 92 / `Specifics for Bayesian Analysis` (PDF pp. 7455–7466).
 * Discriminates: Example 92.14: Bayesian Analysis of Piecewise Exponential Model; explicit statements: BAYES
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data Rats;
label Days ='Days from Exposure to Death';
input Days Status Group @@;
datalines;
143 1 0 164 1 0 188 1 0 188 1 0
190 1 0 192 1 0 206 1 0 209 1 0
213 1 0 216 1 0 220 1 0 227 1 0
230 1 0 234 1 0 246 1 0 265 1 0
304 1 0 216 0 0 244 0 0 142 1 1
156 1 1 163 1 1 198 1 1 205 1 1
232 1 1 232 1 1 233 1 1 233 1 1
233 1 1 233 1 1 239 1 1 240 1 1
261 1 1 280 1 1 280 1 1 296 1 1
296 1 1 323 1 1 204 0 1 344 0 1
;
proc phreg data=Rats;
model Days*Status(0)=Group;
bayes seed=1 piecewise=hazard statistics=(summary interval)
diagnostics=(autocorr geweke ess) nmc=1000 nbi=200;
run;
proc phreg data=Rats;
model Days*Status(0)=Group;
bayes seed=1 spline statistics=(summary interval)
diagnostics=(autocorr geweke ess) nmc=1000 nbi=200;
run;

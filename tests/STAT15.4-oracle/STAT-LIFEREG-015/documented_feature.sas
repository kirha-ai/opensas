/* STAT-LIFEREG-015: LIFEREG — Computational Resources
 * Source: S154 / Chapter 76 / `Computational Resources` (PDF p. 5583).
 * Discriminates: Getting Started: LIFEREG Procedure
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data Headache;
input Minutes Group Censor @@;
datalines;
11 1 0 12 1 0 19 1 0 19 1 0
19 1 0 19 1 0 21 1 0 20 1 0
21 1 0 21 1 0 20 1 0 21 1 0
20 1 0 21 1 0 25 1 0 27 1 0
30 1 0 21 1 1 24 1 1 14 2 0
16 2 0 16 2 0 21 2 0 21 2 0
23 2 0 23 2 0 23 2 0 23 2 0
25 2 1 23 2 0 24 2 0 24 2 0
26 2 1 32 2 1 30 2 1 30 2 0
32 2 1 20 2 1
;
proc lifereg data=Headache;
class Group;
model Minutes*Censor(1)=Group;
output out=New cdf=Prob;
run;
proc sgplot data=New;
scatter x=Minutes y=Prob / group=Group;
discretelegend;
run;
data Fan;
input Lifetime Censor@@;
datalines;
450 0 460 1 1150 0 1150 0 1560 1
1600 0 1660 1 1850 1 1850 1 1850 1
1850 1 1850 1 2030 1 2030 1 2030 1
2070 0 2070 0 2080 0 2200 1 3000 1
3000 1 3000 1 3000 1 3100 0 3200 1
3450 0 3750 1 3750 1 4150 1 4150 1
4150 1 4150 1 4300 1 4300 1 4300 1
4300 1 4600 0 4850 1 4850 1 4850 1
4850 1 5000 1 5000 1 5000 1 6100 1
6100 0 6100 1 6100 1 6300 1 6450 1
6450 1 6700 1 7450 1 7800 1 7800 1
8100 1 8100 1 8200 1 8500 1 8500 1
8500 1 8750 1 8750 0 8750 1 9400 1
9900 1 10100 1 10100 1 10100 1 11500 1
;
ods graphics on;
proc lifereg data=Fan;
model Lifetime*Censor( 1 )= / dist=lognormal;
bayes seed=1 outpost=Post nmc=1000 nbi=200;
run;
data Prob;
set Post;
Frac = ProbNorm(( log(8000) - Intercept ) / Scale );
label Frac= 'Fraction Failing in 8000 Hours';
run;
proc means data = Prob(keep=Frac) n mean p10 p25 p50 p75 p90;
run;

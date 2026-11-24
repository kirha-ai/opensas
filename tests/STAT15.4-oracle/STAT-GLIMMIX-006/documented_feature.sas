/* STAT-GLIMMIX-006: GLIMMIX — Maximum Likelihood Estimation Based on Laplace Approximation
 * Source: S154 / Chapter 52 / `Maximum Likelihood Estimation Based on Laplace Approximation` (PDF pp. 3835–3838).
 * Discriminates: Example 52.11: Maximum Likelihood in Proportional Odds Model with Random Effects
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data foot_mv;
input yr b1 b2 b3 k1 k2 k3;
sire = _n_;
datalines;
1 1 0 0 52 25 0
1 1 0 0 49 17 1
1 1 0 0 50 13 1
1 1 0 0 42 9 0
1 1 0 0 74 15 0
1 1 0 0 54 8 0
1 1 0 0 96 12 0
1 -1 1 0 57 52 9
1 -1 1 0 55 27 5
1 -1 1 0 70 36 4
1 -1 1 0 70 37 3
1 -1 1 0 82 21 1
1 -1 1 0 75 19 0
1 -1 -1 0 17 12 10
1 -1 -1 0 13 23 3
1 -1 -1 0 21 17 3
-1 0 0 1 37 41 23
-1 0 0 1 47 24 12
-1 0 0 1 46 25 9
-1 0 0 1 79 32 11
-1 0 0 1 50 23 5
-1 0 0 1 63 18 8
-1 0 0 -1 30 20 9
-1 0 0 -1 31 33 3
-1 0 0 -1 28 18 4
-1 0 0 -1 42 27 4
-1 0 0 -1 35 22 2
-1 0 0 -1 33 18 3
-1 0 0 -1 35 17 4
-1 0 0 -1 26 13 2
-1 0 0 -1 37 15 2
-1 0 0 -1 36 14 1
-1 0 0 -1 63 20 3
-1 0 0 -1 41 8 1
;
data footshape;
set foot_mv;
array k{3};
do Shape = 1 to 3;
count = k{Shape};
output;
end;
drop k:;
run;
proc glimmix data=footshape method=quad;
class sire;
model Shape = yr b1 b2 b3 / s link=cumprobit dist=multinomial;
random int / sub=sire s cl;
ods output Solutionr=solr;
freq count;
run;
ods select FitStatistics CovParms Covtests;
proc glimmix data=footshape method=quad;
class sire;
model Shape = yr b1 b2 b3 / link=cumprobit dist=multinomial;
random int / sub=sire;
covtest GLM;
freq count;
run;
proc sort data=solr;
by Estimate;
run;
data solr;
set solr;
length sire $2;
obs = _n_;
sire = left(substr(Subject,6,2));
run;
proc sgplot data=solr;
scatter x=obs y=estimate /
markerchar = sire
yerrorupper = upper
yerrorlower = lower;
xaxis grid label='Sire Rank' values=(1 5 10 15 20 25 30);
yaxis grid label='Predicted Sire Effect';
run;

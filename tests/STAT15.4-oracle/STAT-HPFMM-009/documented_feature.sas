/* STAT-HPFMM-009: HPFMM — BAYES / Metropolis-Hastings Algorithm / Prior Distributions
 * Source: S154 / Chapter 58 / `BAYES Statement` (PDF pp. 4544–4553); S154 / Chapter 58 / `Metropolis-Hastings Algorithm` (PDF pp. 4580–4581); S154 / Chapter 58 / `Prior Distributions` (PDF pp. 4582–4583).
 * Discriminates: Getting Started: HPFMM Procedure; explicit statements: BAYES
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data yeast;
input count f;
n = 5;
datalines;
0 213
1 128
2 37
3 18
4 3
5 1
;
proc hpfmm data=yeast seed=314159;
model count/n = / k=2;
freq f;
run;
proc hpfmm data=yeast seed=314159;
model count/n = / k=2;
freq f;
id f n;
output out=hpfmmout pred(components) posterior;
run;
data hpfmmout;
set hpfmmout;
PredCount_1 = post_1 * f;
PredCount_2 = post_2 * f;
run;
proc print data=hpfmmout;
run;
ods graphics on;
proc hpfmm data=yeast seed=12345;
model count/n = / k=2;
freq f;
performance nthreads=2;
bayes nmc=1000 nbi=200;
run;
ods graphics off;
data catch;
input gender $ age count @@;
datalines;
F 54 18 M 37 0 F 48 12 M 27 0
M 55 0 M 32 0 F 49 12 F 45 11
M 39 0 F 34 1 F 50 0 M 52 4
M 33 0 M 32 0 F 23 1 F 17 0
F 44 5 M 44 0 F 26 0 F 30 0
F 38 0 F 38 0 F 52 18 M 23 1
F 23 0 M 32 0 F 33 3 M 26 0
F 46 8 M 45 5 M 51 10 F 48 5
F 31 2 F 25 1 M 22 0 M 41 0
M 19 0 M 23 0 M 31 1 M 17 0
F 21 0 F 44 7 M 28 0 M 47 3
M 23 0 F 29 3 F 24 0 M 34 1
F 19 0 F 35 2 M 39 0 M 43 6
;
proc hpfmm data=catch seed=314159;
class gender;
model count = gender*age / dist=Poisson;
run;
proc hpfmm data=catch seed=314159;
class gender;
model count = gender*age / dist=Poisson ;
model + / dist=Constant;
run;
proc hpfmm data=catch seed=12345;
class gender;
model count = gender*age / dist=Poisson;
model + / dist=constant;
performance nthreads=2;
bayes nmc=1000 nbi=200;
run;
ods graphics on;
ods select TADPanel;
proc hpfmm data=catch seed=12345;
class gender;
model count = gender*age / dist=Poisson;
model + / dist=constant;
performance nthreads=2;
bayes nmc=1000 nbi=200;
run;
ods graphics off;
title "HPFMM Analysis of Galaxies Data";
data galaxies;
input velocity @@;
v = velocity / 1000;
datalines;
9172 9350 9483 9558 9775 10227 10406 16084 16170 18419
18552 18600 18927 19052 19070 19330 19343 19349 19440 19473
19529 19541 19547 19663 19846 19856 19863 19914 19918 19973
19989 20166 20175 20179 20196 20215 20221 20415 20629 20795
20821 20846 20875 20986 21137 21492 21701 21814 21921 21960
22185 22209 22242 22249 22314 22374 22495 22746 22747 22888
22914 23206 23241 23263 23484 23538 23542 23666 23706 23711
24129 24285 24289 24366 24717 24990 25633 26960 26995 32065
32789 34279
;
title2 "Three to Seven Components, Unequal Variances";
ods graphics on;
proc hpfmm data=galaxies criterion=AIC seed=314159;
model v = / kmin=3 kmax=7;
ods exclude IterHistory OptInfo ComponentInfo;
run;
title2 "Three to Seven Components, Equal Variances";
proc hpfmm data=galaxies criterion=AIC gconv=0 seed=314159;
model v = / kmin=3 kmax=7 equate=scale;
run;
title2 "Five Components, Equal Variances = 0.9025";
proc hpfmm data=galaxies seed=314159;
model v = / K=5 equate=scale;
restrict int 0 (scale 1) = 0.9025;
run;
ods graphics off;
run;
quit;

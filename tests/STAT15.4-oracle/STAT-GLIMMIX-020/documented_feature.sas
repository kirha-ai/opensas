/* STAT-GLIMMIX-020: GLIMMIX — CONTRAST / COVTEST / ESTIMATE
 * Source: S154 / Chapter 52 / `CONTRAST Statement` (PDF pp. 3732–3736); S154 / Chapter 52 / `COVTEST Statement` (PDF pp. 3736–3744); S154 / Chapter 52 / `ESTIMATE Statement` (PDF pp. 3744–3750).
 * Discriminates: Example 52.13: Response Surface Comparisons with Multiplicity Adjustments; explicit statements: CONTRAST, COVTEST, ESTIMATE
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data Clinical;
do Center = 1, 2;
do Gender = 'F','M';
do Drug = 'A','P';
input nPatient @@;
do iPatient = 1 to nPatient;
input ID Age (t0-t4) (1.) @@;
output;
end;
end;
end;
end;
datalines;
2 53 32 12242 18 47 22344
5 5 13 44444 19 31 21022 25 35 10000 28 36 23322
36 45 22221
25 54 11 44442 12 14 23332 51 15 02333 20 20 33231
16 22 12223 50 22 21344 3 23 33443 32 23 23444
56 25 23323 35 26 12232 26 26 22222 21 26 24142
8 28 12212 30 28 00121 33 30 33442 11 30 34443
42 31 12311 9 31 33444 37 31 02321 23 32 34433
6 34 11211 22 46 43434 24 48 23202 38 50 22222
48 57 33434
24 43 13 34444 41 14 22123 34 15 22332 29 19 23300
15 20 44444 13 23 33111 27 23 44244 55 24 34443
17 25 11222 45 26 24243 40 26 12122 44 27 12212
49 27 33433 39 23 21111 2 28 20000 14 30 10000
31 37 10000 10 37 32332 7 43 23244 52 43 11132
4 44 34342 1 46 22222 46 49 22222 47 63 22222
4 30 37 13444 52 39 23444 23 60 44334 54 63 44444
12 28 31 34444 5 32 32234 21 36 33213 50 38 12000
1 39 12112 48 39 32300 7 44 34444 38 47 23323
8 48 22100 11 48 22222 4 51 34244 17 58 14220
23 12 13 44444 10 14 14444 27 19 33233 47 20 24443
16 20 21100 29 21 33444 20 24 44444 25 25 34331
15 25 34433 2 25 22444 9 26 23444 49 28 23221
55 31 44444 43 34 24424 26 35 44444 14 37 43224
36 41 34434 51 43 33442 37 52 12122 19 55 44444
32 55 22331 3 58 44444 53 68 23334
16 39 11 34444 40 14 21232 24 15 32233 41 15 43334
33 19 42233 34 20 32444 13 20 14444 45 33 33323
22 36 24334 18 38 43000 35 42 32222 44 43 21000
6 45 34212 46 48 44000 31 52 23434 42 66 33344
;
%macro Contrast(from,to,byA,byT);
%let nCmp=0;
%do age=&from %to &to %by &byA;
%do t0=0 %to 4 %by &byT;
%let nCmp=%eval(&nCmp+1);
%end; %end;
%let iCmp=0;
%do age=&from %to &to %by &byA;
%do t0=0 %to 4 %by &byT;
%let iCmp=%eval(&iCmp+1);
"&age &t0" drug 1 -1 drug*age &age -&age drug*t0 &t0 -&t0
%if &iCmp < &nCmp %then %do; , %end;
%end; %end;
%mend;

proc glimmix data=clinical;
t = (t3+t4)/2;
class drug;
model t = drug t0 age drug*age drug*t0;
estimate %contrast(20,60,20,2)
/ adjust=simulate(seed=1)
stepdown(type=logical);
ods output Estimates=EstStepDown;
run;
proc sort data=EstStepDown;
by Probt;
run;
proc print data=EstStepDown(obs=20);
var Label Estimate StdErr Probt AdjP;
run;
ods output Estimates=EstAdjust;
proc glimmix data=clinical;
t = (t3+t4)/2;
class drug;
model t = drug t0 age drug*age drug*t0;
estimate %contrast(20,60,20,2)
/ adjust=simulate(seed=1);
ods output Estimates=EstAdjust;
run;
proc glimmix data=clinical;
t = (t3+t4)/2;
class drug;
model t = drug t0 age drug*age drug*t0;
estimate %contrast(20,60,20,2);
ods output Estimates=EstUnAdjust;
run;
data clinical_uv;
set clinical;
array time{2} t3-t4;
do i=1 to 2;
rating = time{i};
output;
end;
run;
proc glimmix data=clinical_uv method=laplace;
class center id drug;
model rating = drug t0 age drug*age drug*t0 /
dist=multinomial link=cumlogit;
random intercept / subject=id(center);
covtest 0;
estimate %contrast(20,60,20,2)
/ adjust=simulate(seed=1)
stepdown(type=logical);
ods output Estimates=EstStepDownMulti;
run;
proc sort data=EstStepDownMulti;
by Probt;
run;
proc print data=EstStepDownMulti(obs=20);
var Label Estimate StdErr Probt AdjP;
run;

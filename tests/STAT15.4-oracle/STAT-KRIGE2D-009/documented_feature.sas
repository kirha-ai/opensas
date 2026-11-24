/* STAT-KRIGE2D-009: KRIGE2D — Zonal Anisotropy / Anisotropic Nugget Effect / Introduction
 * Source: S154 / Chapter 74 / `Zonal Anisotropy` (PDF pp. 5478–5482); S154 / Chapter 74 / `Anisotropic Nugget Effect` (PDF p. 5482); S154 / Chapter 74 / `Introduction` (PDF pp. 5482–5483).
 * Discriminates: Example 74.2: Investigating the Effect of Model Specification on Spatial Prediction
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

title 'Effect of Model Specification on Prediction';
data thick;
input East North Thick @@;
label Thick='Coal Seam Thickness';
datalines;
0.7 59.6 34.1 2.1 82.7 42.2 4.7 75.1 39.5
4.8 52.8 34.3 5.9 67.1 37.0 6.0 35.7 35.9
6.4 33.7 36.4 7.0 46.7 34.6 8.2 40.1 35.4
13.3 0.6 44.7 13.3 68.2 37.8 13.4 31.3 37.8
17.8 6.9 43.9 20.1 66.3 37.7 22.7 87.6 42.8
23.0 93.9 43.6 24.3 73.0 39.3 24.8 15.1 42.3
24.8 26.3 39.7 26.4 58.0 36.9 26.9 65.0 37.8
27.7 83.3 41.8 27.9 90.8 43.3 29.1 47.9 36.7
29.5 89.4 43.0 30.1 6.1 43.6 30.8 12.1 42.8
32.7 40.2 37.5 34.8 8.1 43.3 35.3 32.0 38.8
37.0 70.3 39.2 38.2 77.9 40.7 38.9 23.3 40.5
39.4 82.5 41.4 43.0 4.7 43.3 43.7 7.6 43.1
46.4 84.1 41.5 46.7 10.6 42.6 49.9 22.1 40.7
51.0 88.8 42.0 52.8 68.9 39.3 52.9 32.7 39.2
55.5 92.9 42.2 56.0 1.6 42.7 60.6 75.2 40.1
62.1 26.6 40.1 63.0 12.7 41.8 69.0 75.6 40.1
70.5 83.7 40.9 70.9 11.0 41.7 71.5 29.5 39.8
78.1 45.5 38.7 78.2 9.1 41.7 78.4 20.0 40.8
80.5 55.9 38.7 81.1 51.0 38.6 83.8 7.9 41.6
84.5 11.0 41.5 85.2 67.3 39.4 85.5 73.0 39.8
86.7 70.4 39.6 87.2 55.7 38.8 88.1 0.0 41.6
88.4 12.1 41.3 88.4 99.6 41.2 88.8 82.9 40.5
88.9 6.2 41.5 90.6 7.0 41.5 90.7 49.6 38.9
91.5 55.4 39.0 92.9 46.8 39.1 93.4 70.9 39.7
55.8 50.5 38.1 96.2 84.3 40.3 98.2 58.2 39.5
;
ods graphics on;
proc variogram data=thick noprint;
store out=SemivStoreGau / label='Thickness Gaussian Model';
compute lagd=7 maxlag=10;
coord xc=East yc=North;
model form=gau;
var Thick;
run;
proc krige2d data=thick outest=pred1 noprint;
restore in=SemivStoreGau;
coordinates xc=East yc=North;
predict var=Thick r=60;
model storeselect;
grid x=0 to 100 by 10 y=0 to 100 by 10;
run;
proc variogram data=thick plots(only)=fit;
store out=SemivStoreSph / label='Thickness Sph Model';
compute lagd=7 maxlag=10;
coord xc=East yc=North;
model form=sph;
var Thick;
run;
proc krige2d data=thick outest=pred2 noprint;
restore in=SemivStoreSph;
coordinates xc=East yc=North;
predict var=Thick r=60;
model storeselect;
grid x=0 to 100 by 10 y=0 to 100 by 10;
run;
data compare;
merge pred1(rename=(estimate=g_prd stderr=g_std))
pred2(rename=(estimate=s_prd stderr=s_std));
prdRelDif = ((g_prd-s_prd) / s_prd) * 100;
stdRelDif = ((g_std-s_std) / s_std) * 100;
run;
proc means data=compare;
var prdRelDif stdRelDif;
run;
ods graphics off;
run;
quit;

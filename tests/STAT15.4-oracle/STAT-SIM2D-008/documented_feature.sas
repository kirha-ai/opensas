/* STAT-SIM2D-008: SIM2D — ODS Graphics
 * Source: S154 / Chapter 112 / `ODS Graphics` (PDF pp. 9344–9345).
 * Discriminates: Getting Started: SIM2D Procedure
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

ods graphics on;
ods trace on;
ods trace on;

title 'Using PROC SIM2D for Spatial Simulation';
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
proc sim2d data=thick outsim=sim plot=(observ sim);
coordinates xc=East yc=North;
simulate var=Thick numreal=100 seed=79931
scale=7.4599 range=30.1111 nugget=1e-8 form=gauss;
mean 40.1173;
grid x=0 to 100 by 25 y=0 to 100 by 25;
run;
data selected;
set sim(where=((gxc=0 and gyc=0) or (gxc=75 and gyc=75)));
label gxc = "X-coord";
label gyc = "Y-coord";
run;
proc sort data=selected;
by gxc gyc;
run;
proc means data=selected Mean Std Max;
class gxc gyc;
ways 2;
where ( ((gxc = 0) & (gyc = 0))
| ((gxc = 75) & (gyc = 75)));
var SValue;
run;
ods graphics off;
run;
quit;
ods trace off;
ods trace off;
ods graphics off;

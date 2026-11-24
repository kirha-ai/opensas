/* STAT-BGLIMM-015: BGLIMM — Official examples and feature integration regression
 * Source: S154 / Chapter 31 / `Examples: BGLIMM Procedure` (PDF pp. 1332–1362).
 * Discriminates: Example 31.4: Repeated Growth Measurements with Group Difference
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data pr;
input Person Gender $ y1 y2 y3 y4;
Distance=y1;
Age=8;
Time=1;
output;
Distance=y2;
Age=10;
Time=2;
output;
Distance=y3;
Age=12;
Time=3;
output;
Distance=y4;
Age=14;
Time=4;
output;
drop y1-y4;
datalines;
1 F 21.0 20.0 21.5 23.0
2 F 21.0 21.5 24.0 25.5
3 F 20.5 24.0 24.5 26.0
4 F 23.5 24.5 25.0 26.5
5 F 21.5 23.0 22.5 23.5
6 F 20.0 21.0 21.0 22.5
7 F 21.5 22.5 23.0 25.0
8 F 23.0 23.0 23.5 24.0
9 F 20.0 21.0 22.0 21.5
10 F 16.5 19.0 19.0 19.5
11 F 24.5 25.0 28.0 28.0
12 M 26.0 25.0 29.0 31.0
13 M 21.5 22.5 23.0 26.5
14 M 23.0 22.5 24.0 27.5
15 M 25.5 27.5 26.5 27.0
16 M 20.0 23.5 22.5 26.0
17 M 24.5 25.5 27.0 28.5
18 M 22.0 22.0 24.5 26.5
19 M 24.0 21.5 24.5 25.5
20 M 23.0 20.5 31.0 26.0
21 M 27.5 28.0 31.0 31.5
22 M 23.0 23.0 23.5 25.0
23 M 21.5 23.5 24.0 28.0
24 M 17.0 24.5 26.0 29.5
25 M 22.5 25.5 25.5 26.0
26 M 23.0 24.5 26.0 30.0
27 M 22.0 21.5 23.5 25.0
;
proc bglimm data=pr seed=475193 outpost=pr_out nmc=1000 nbi=200;
by Gender;
class Person Time;
model Distance = Age;
repeated Time / subject=Person type=un r;
run;
proc bglimm data=pr seed=475193 outpost=pr_out nmc=1000 nbi=200;
class Person Gender Time;
model Distance = Age|Gender;
repeated Time / type=un subject=Person group=Gender r;
run;
proc bglimm data=pr seed=475193 outpost=pr_out nmc=1000 nbi=200;
class Person Gender Time;
model Distance = Age|Gender;
repeated Time / type=un subject=Person group=Gender r;
estimate 'Girls Intercept' Int 1 Gender 1 0;
estimate 'Boys Intercept' Int 1 Gender 0 1;
estimate 'Girls Slope' Age 1 Age*Gender 1 0;
estimate 'Boys Slope' Age 1 Age*Gender 0 1;
run;
data prob;
set pr_out;
pDiff = boys_slope - girls_slope;
prob = (pDiff > 0);
keep pDiff prob;
run;
%sumint(data=prob, var=pDiff prob)
proc bglimm data=pr seed=475193 outpost=pr_out nmc=1000 nbi=200;
class Person Gender Time;
model Distance = Gender Age*Gender / noint;
repeated Time / type=un subject=Person group=Gender;
estimate 'Intercept Difference' Gender 1 -1;
estimate 'Slope Difference' Gender*Age 1 -1;
estimate 'Girl at Age 11' Gender 1 0 Gender*Age 11 0;
estimate 'Boy at Age 11' Gender 0 1 Gender *Age 0 11;
run;

/* STAT-BCHOICE-008: BCHOICE — Gamerman Algorithm / Tuning the Random Walk Metropolis in Logit Models / Autocall Macros for Postprocessing
 * Source: S154 / Chapter 30 / `Gamerman Algorithm` (PDF pp. 1216–1218); S154 / Chapter 30 / `Tuning the Random Walk Metropolis in Logit Models` (PDF pp. 1218–1220); S154 / Chapter 30 / `Autocall Macros for Postprocessing` (PDF pp. 1220–1222).
 * Discriminates: Example 30.2: Nested Logit Modeling
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data Travel;
input AutoTime PlanTime TranTime Age Chosen $;
AgeCtr=Age-34;
datalines;
10.0 4.5 10.5 32 Plane

5.5 4.0 7.5 13 Auto
4.5 6.0 5.5 41 Transit
3.5 2.0 5.0 41 Transit
1.5 4.5 4.0 47 Auto
10.5 3.0 10.5 24 Plane
7.0 3.0 9.0 27 Auto
9.0 3.5 9.0 21 Plane
4.0 5.0 5.5 23 Auto
22.0 4.5 22.5 30 Plane
7.5 5.5 10.0 58 Plane
11.5 3.5 11.5 36 Transit
3.5 4.5 4.5 43 Auto
12.0 3.0 11.0 33 Plane
18.0 5.5 20.0 30 Plane
23.0 5.5 21.5 28 Plane
4.0 3.0 4.5 44 Plane
5.0 2.5 7.0 37 Transit
3.5 2.0 7.0 45 Auto
12.5 3.5 15.5 35 Plane
1.5 4.0 2.0 22 Auto
;

run;

data Travel2(keep=Subject Mode TravTime Age AgeCtr Choice);
array Times[3] AutoTime PlanTime TranTime;
array Allmodes[3] $ _temporary_ ('Auto' 'Plane' 'Transit');
set Travel;
Subject = _n_;
do i = 1 to 3;
Mode = Allmodes[i];
TravTime = Times[i];
Choice = (Chosen eq Mode);
output;
end;
run;
proc bchoice data=Travel2 seed=124 nmc=1000 nthin=2 dic nbi=200;
class Mode Subject / param=ref order=data;
model Choice = Mode TravTime / choiceset=(Subject) type=nlogit nest=(1 2 1);
run;
proc bchoice data=Travel2 seed=124 nmc=1000 nthin=2 dic nbi=200;
class Mode Subject / param=ref order=data;
model Choice = Mode TravTime / choiceset=(Subject);
run;

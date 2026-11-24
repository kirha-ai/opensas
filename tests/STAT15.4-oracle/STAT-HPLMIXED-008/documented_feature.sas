/* STAT-HPLMIXED-008: HPLMIXED — REPEATED
 * Source: S154 / Chapter 60 / `REPEATED Statement` (PDF pp. 4717–4718).
 * Discriminates: Example 60.1: Computing BLUPs for a Large Number of Subjects; explicit statements: REPEATED
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

%let NCenter = 100;
%let NPatient = %eval(&NCenter*50);
%let NTime = 3;
%let SigmaC = 2.0;
%let SigmaP = 4.0;
%let SigmaE = 8.0;
%let Seed = 12345;
data WeekSim;
keep Gender Center Patient Time Measurement;
array PGender{&NPatient};
array PCenter{&NPatient};
array PEffect{&NPatient};
array CEffect{&NCenter};
array GEffect{2};
do Center = 1 to &NCenter;
CEffect{Center} = sqrt(&SigmaC)*rannor(&Seed);
end;
GEffect{1} = 10*ranuni(&Seed);
GEffect{2} = 10*ranuni(&Seed);
do Patient = 1 to &NPatient;
PGender{Patient} = 1 + int(2 *ranuni(&Seed));
PCenter{Patient} = 1 + int(&NCenter*ranuni(&Seed));
PEffect{Patient} = sqrt(&SigmaP)*rannor(&Seed);
end;
do Patient = 1 to &NPatient;
Gender = PGender{Patient};
Center = PCenter{Patient};
Mean = 1 + GEffect{Gender} + CEffect{Center} + PEffect{Patient};
do Time = 1 to &nTime;
Measurement = Mean + sqrt(&SigmaE)*rannor(&Seed);
output;
end;
end;
run;
ods exclude all;
proc hplmixed data=WeekSim blup;
class Gender Center Patient Time;
model Measurement = Gender;
random Center / s;
repeated Time / sub=Patient type=un;
parms 1.7564
11.4555
3.6883 11.2071
4.5951 3.6311 12.1050;
ods output SolutionR=BLUPs;
run;
ods exclude none;
proc sort data=BLUPs;
by Estimate;
run;
data BLUPs;
set BLUPs;
Rank = _N_;
run;
proc print data=BLUPs;
where ((Rank <= 5) | (Rank >= 96));
var Center Estimate;
run;

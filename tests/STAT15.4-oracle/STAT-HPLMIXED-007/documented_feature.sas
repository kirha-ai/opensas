/* STAT-HPLMIXED-007: HPLMIXED — RANDOM / Estimating Fixed and Random Effects in the Mixed Model
 * Source: S154 / Chapter 60 / `RANDOM Statement` (PDF pp. 4711–4717); S154 / Chapter 60 / `Estimating Fixed and Random Effects in the Mixed Model` (PDF pp. 4725–4726).
 * Discriminates: Getting Started: HPLMIXED Procedure; explicit statements: RANDOM
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data SchoolSample;
do SchoolID = 1 to 300;
do nID = 1 to 25;
Neighborhood = (SchoolID-1)*5 + nId;
bInt = 5 *ranuni(1);
bTime = 5 *ranuni(1);
bTime2 = ranuni(1);
do sID = 1 to 2;
do Time = 1 to 4;
Math = bInt + bTime*Time + bTime2*Time*Time + rannor(2);
output;
end;
end;
end;
end;
run;
proc hplmixed data=SchoolSample;
class Neighborhood SchoolID;
model Math = Time Time*Time / solution;
random int Time Time *Time / sub=Neighborhood(SchoolID) type=un;
run;

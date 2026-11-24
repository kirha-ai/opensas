/* STAT-HPLMIXED-003: HPLMIXED — CLASS / MODEL
 * Source: S154 / Chapter 60 / `CLASS Statement` (PDF p. 4706); S154 / Chapter 60 / `MODEL Statement` (PDF pp. 4707–4708).
 * Discriminates: Getting Started: HPLMIXED Procedure; explicit statements: CLASS, MODEL
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

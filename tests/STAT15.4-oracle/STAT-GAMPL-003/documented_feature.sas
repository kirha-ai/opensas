/* STAT-GAMPL-003: GAMPL — CLASS / MODEL
 * Source: S154 / Chapter 49 / `CLASS Statement` (PDF pp. 3362–3363); S154 / Chapter 49 / `MODEL Statement` (PDF pp. 3363–3372).
 * Discriminates: Getting Started: GAMPL Procedure; explicit statements: MODEL
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

%let off0 = offsetmin=0 offsetmax=0
linearopts=(thresholdmin=0 thresholdmax=0);
proc template;
define statgraph surface;
dynamic _title _z;
begingraph / designwidth=defaultDesignHeight;
entrytitle _title;
layout overlay / xaxisopts=(&off0) yaxisopts=(&off0);
contourplotparm z=_z y=Latitude x=Longitude / gridded=FALSE;
endlayout;
endgraph;
end;
run;
proc sgrender data=sashelp.Vote1980 template=surface;
dynamic _title = 'US County Vote Proportion in the 1980 Election'
_z = 'LogVoteRate';
run;
ods graphics on;
proc gampl data=sashelp.Vote1980 plots seed=12345;
model LogVoteRate = spline(Pop ) spline(Edu) spline(Houses)
spline(Income) spline(Longitude Latitude);
id Longitude Latitude;
output out=VotePred;
run;
proc sgrender data=VotePred template=surface;
dynamic _title='Predicted US County Vote Proportion in the 1980 Election'
_z ='Pred';
run;

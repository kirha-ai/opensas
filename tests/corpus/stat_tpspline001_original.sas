/* STAT-TPSPLINE-001: the unchanged oracle program documented_feature.sas
 * reproduced completely, PROC PRINT step included; the expected listing is
 * the SAS 15.4 reference listing (rc 0), compared word by word. Invented data.
 */
/* STAT-TPSPLINE-001: TPSPLINE — Data input, variable roles, and basic options
 * Source: S154 / Chapter 125 / `PROC TPSPLINE Statement` (PDF pp. 10298–10302); S154 / Chapter 125 / `BY Statement` (PDF pp. 10302–10303); S154 / Chapter 125 / `FREQ Statement` (PDF p. 10303); S154 / Chapter 125 / `ID Statement` (PDF p. 10303).
 * Discriminates: Verified default procedure context; explicit statements: BY
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data surface;
do x1=-1 to 1 by 0.5;
do x2=-1 to 1 by 0.5;
do rep=1 to 2;
y=3+x1-2*x2+0.5*x1*x2+0.1*cos(rep+x1+x2);
output;
end;
end;
end;
run;
proc tpspline data=surface;
model y=(x1 x2) / lognlambda=(-4 to -2.5 by 0.5);
output out=predicted pred uclm lclm;
run;
proc print data=predicted(obs=12) noobs;
run;

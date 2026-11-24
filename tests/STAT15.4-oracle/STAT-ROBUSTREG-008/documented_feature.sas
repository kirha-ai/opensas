/* STAT-ROBUSTREG-008: ROBUSTREG — OUTPUT / OUTEST= Data Set
 * Source: S154 / Chapter 107 / `OUTPUT Statement` (PDF pp. 8796–8798); S154 / Chapter 107 / `OUTEST= Data Set` (PDF pp. 8824–8825).
 * Discriminates: Example 107.2: Robust ANOVA; explicit statements: OUTPUT
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data recover;
input T1 $ T2 $ time @@;
datalines;
0 0 20.2 0 0 23.9 0 0 21.9 0 0 42.4
1 0 27.2 1 0 34.0 1 0 27.4 1 0 28.5
0 1 25.9 0 1 34.5 0 1 25.1 0 1 34.2
1 1 35.0 1 1 33.9 1 1 38.3 1 1 39.9
;
proc glm data=recover;
class T1 T2;
model time = T1 T2 T1*T2;
run;
proc robustreg data=recover;
class T1 T2;
model time = T1 T2 T1*T2 / diagnostics;
T1_T2: test T1*T2;
output out=robout r=resid sr=stdres;
run;

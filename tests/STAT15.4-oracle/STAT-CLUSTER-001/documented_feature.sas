/* STAT-CLUSTER-001: CLUSTER — Data input, variable roles, and basic options
 * Source: S154 / Chapter 40 / `PROC CLUSTER Statement` (PDF pp. 2498–2508); S154 / Chapter 40 / `BY Statement` (PDF pp. 2508–2509); S154 / Chapter 40 / `COPY Statement` (PDF p. 2509); S154 / Chapter 40 / `FREQ Statement` (PDF p. 2509); S154 / Chapter 40 / `ID Statement` (PDF pp. 2509–2510); S154 / Chapter 40 / `VAR Statement` (PDF pp. 2510–2511); S154 / Chapter 40 / `Missing Values` (PDF p. 2521).
 * Discriminates: Verified default procedure context; explicit statements: ID
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

proc print noobs data=sashelp.mileages;
run;
title 'Cluster Analysis of Flying Mileages Between 10 American Cities';
ods graphics on;
title2 'Using METHOD=AVERAGE';
proc cluster data=sashelp.mileages(type=distance) method=average pseudo;
id City;
run;
title2 'Using METHOD=CENTROID';
proc cluster data=sashelp.mileages(type=distance) method=centroid pseudo;
id City;
run;
title2 'Using METHOD=DENSITY K=3';
proc cluster data=sashelp.mileages(type=distance) method=density k=3;
id City;
run;
title2 'Using METHOD=SINGLE';
proc cluster data=sashelp.mileages(type=distance) method=single;
id City;
run;
title2 'Using METHOD=TWOSTAGE K=3';
proc cluster data=sashelp.mileages(type=distance) method=twostage k=3;
id City;
run;
title2 'Using METHOD=WARD';
proc cluster data=sashelp.mileages(type=distance) method=ward pseudo;
id City;
run;

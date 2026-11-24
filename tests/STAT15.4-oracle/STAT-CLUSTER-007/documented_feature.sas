/* STAT-CLUSTER-007: CLUSTER — Displayed Output / ODS Table Names
 * Source: S154 / Chapter 40 / `Displayed Output` (PDF pp. 2525–2528); S154 / Chapter 40 / `ODS Table Names` (PDF p. 2528).
 * Discriminates: Example 40.1: Cluster Analysis of Flying Mileages between 10 American Cities
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

ods trace on;
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
ods trace off;

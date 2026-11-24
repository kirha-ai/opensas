/* STAT-SASHELP-006: SASHELP example data — Margarine Data / Flying Mileages between 10 US Cities Data / Earthquake Locations in the United States
 * Source: S154 / Sashelp Data Sets / `Margarine Data` (PDF pp. 10918–10919); S154 / Sashelp Data Sets / `Flying Mileages between 10 US Cities Data` (PDF pp. 10919–10921); S154 / Sashelp Data Sets / `Earthquake Locations in the United States` (PDF pp. 10921–10922).
 * Discriminates: Published SASHELP data availability, row counts, first observations and descriptors: margarin, mileages, quakes, springs
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

proc contents data=sashelp.margarin out=_descriptor(keep=name type length varnum label) noprint; run;
proc sort data=_descriptor; by varnum; run;
proc print data=_descriptor noobs; run;
proc print data=sashelp.margarin(obs=5) noobs; run;
proc sql; select count(*) as Observations from sashelp.margarin; quit;
proc contents data=sashelp.mileages out=_descriptor(keep=name type length varnum label) noprint; run;
proc sort data=_descriptor; by varnum; run;
proc print data=_descriptor noobs; run;
proc print data=sashelp.mileages(obs=5) noobs; run;
proc sql; select count(*) as Observations from sashelp.mileages; quit;
proc contents data=sashelp.quakes out=_descriptor(keep=name type length varnum label) noprint; run;
proc sort data=_descriptor; by varnum; run;
proc print data=_descriptor noobs; run;
proc print data=sashelp.quakes(obs=5) noobs; run;
proc sql; select count(*) as Observations from sashelp.quakes; quit;
proc contents data=sashelp.springs out=_descriptor(keep=name type length varnum label) noprint; run;
proc sort data=_descriptor; by varnum; run;
proc print data=_descriptor noobs; run;
proc print data=sashelp.springs(obs=5) noobs; run;
proc sql; select count(*) as Observations from sashelp.springs; quit;

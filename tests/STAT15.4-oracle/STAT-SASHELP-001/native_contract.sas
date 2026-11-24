/* STAT-SASHELP-001: SASHELP example data — Baseball Data / Tropical Rain Forest Tree Data / 2003 Birth Weight Data Set
 * Source: S154 / Sashelp Data Sets / `Baseball Data` (PDF pp. 10897–10899); S154 / Sashelp Data Sets / `Tropical Rain Forest Tree Data` (PDF pp. 10899–10901); S154 / Sashelp Data Sets / `2003 Birth Weight Data Set` (PDF pp. 10901–10902).
 * Discriminates: Published SASHELP data availability, row counts, first observations and descriptors: mileages, quakes, springs, thick, vote1980, baseball, bei, birthwgt, bmimen
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

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
proc contents data=sashelp.thick out=_descriptor(keep=name type length varnum label) noprint; run;
proc sort data=_descriptor; by varnum; run;
proc print data=_descriptor noobs; run;
proc print data=sashelp.thick(obs=5) noobs; run;
proc sql; select count(*) as Observations from sashelp.thick; quit;
proc contents data=sashelp.vote1980 out=_descriptor(keep=name type length varnum label) noprint; run;
proc sort data=_descriptor; by varnum; run;
proc print data=_descriptor noobs; run;
proc print data=sashelp.vote1980(obs=5) noobs; run;
proc sql; select count(*) as Observations from sashelp.vote1980; quit;
proc contents data=sashelp.baseball out=_descriptor(keep=name type length varnum label) noprint; run;
proc sort data=_descriptor; by varnum; run;
proc print data=_descriptor noobs; run;
proc print data=sashelp.baseball(obs=5) noobs; run;
proc sql; select count(*) as Observations from sashelp.baseball; quit;
proc contents data=sashelp.bei out=_descriptor(keep=name type length varnum label) noprint; run;
proc sort data=_descriptor; by varnum; run;
proc print data=_descriptor noobs; run;
proc print data=sashelp.bei(obs=5) noobs; run;
proc sql; select count(*) as Observations from sashelp.bei; quit;
proc contents data=sashelp.birthwgt out=_descriptor(keep=name type length varnum label) noprint; run;
proc sort data=_descriptor; by varnum; run;
proc print data=_descriptor noobs; run;
proc print data=sashelp.birthwgt(obs=5) noobs; run;
proc sql; select count(*) as Observations from sashelp.birthwgt; quit;
proc contents data=sashelp.bmimen out=_descriptor(keep=name type length varnum label) noprint; run;
proc sort data=_descriptor; by varnum; run;
proc print data=_descriptor noobs; run;
proc print data=sashelp.bmimen(obs=5) noobs; run;
proc sql; select count(*) as Observations from sashelp.bmimen; quit;

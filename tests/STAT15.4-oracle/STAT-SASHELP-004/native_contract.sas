/* STAT-SASHELP-004: SASHELP example data — El Nino–Southern Oscillation Data / Finland's Lake Laengelmaevesi Fish Catch Data / Exhaust Emissions Data
 * Source: S154 / Sashelp Data Sets / `El Nino–Southern Oscillation Data` (PDF pp. 10909–10910); S154 / Sashelp Data Sets / `Finland's Lake Laengelmaevesi Fish Catch Data` (PDF pp. 10910–10911); S154 / Sashelp Data Sets / `Exhaust Emissions Data` (PDF pp. 10911–10912).
 * Discriminates: Published SASHELP data availability, row counts, first observations and descriptors: enso, fish, gas, iris
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

proc contents data=sashelp.enso out=_descriptor(keep=name type length varnum label) noprint; run;
proc sort data=_descriptor; by varnum; run;
proc print data=_descriptor noobs; run;
proc print data=sashelp.enso(obs=5) noobs; run;
proc sql; select count(*) as Observations from sashelp.enso; quit;
proc contents data=sashelp.fish out=_descriptor(keep=name type length varnum label) noprint; run;
proc sort data=_descriptor; by varnum; run;
proc print data=_descriptor noobs; run;
proc print data=sashelp.fish(obs=5) noobs; run;
proc sql; select count(*) as Observations from sashelp.fish; quit;
proc contents data=sashelp.gas out=_descriptor(keep=name type length varnum label) noprint; run;
proc sort data=_descriptor; by varnum; run;
proc print data=_descriptor noobs; run;
proc print data=sashelp.gas(obs=5) noobs; run;
proc sql; select count(*) as Observations from sashelp.gas; quit;
proc contents data=sashelp.iris out=_descriptor(keep=name type length varnum label) noprint; run;
proc sort data=_descriptor; by varnum; run;
proc print data=_descriptor noobs; run;
proc print data=sashelp.iris(obs=5) noobs; run;
proc sql; select count(*) as Observations from sashelp.iris; quit;

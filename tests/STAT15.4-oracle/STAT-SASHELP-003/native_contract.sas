/* STAT-SASHELP-003: SASHELP example data — 1997 Birth Weight Data / Class Data / Comet Data
 * Source: S154 / Sashelp Data Sets / `1997 Birth Weight Data` (PDF pp. 10906–10907); S154 / Sashelp Data Sets / `Class Data` (PDF pp. 10907–10908); S154 / Sashelp Data Sets / `Comet Data` (PDF pp. 10908–10909).
 * Discriminates: Published SASHELP data availability, row counts, first observations and descriptors: bweight, class, comet, enso
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

proc contents data=sashelp.bweight out=_descriptor(keep=name type length varnum label) noprint; run;
proc sort data=_descriptor; by varnum; run;
proc print data=_descriptor noobs; run;
proc print data=sashelp.bweight(obs=5) noobs; run;
proc sql; select count(*) as Observations from sashelp.bweight; quit;
proc contents data=sashelp.class out=_descriptor(keep=name type length varnum label) noprint; run;
proc sort data=_descriptor; by varnum; run;
proc print data=_descriptor noobs; run;
proc print data=sashelp.class(obs=5) noobs; run;
proc sql; select count(*) as Observations from sashelp.class; quit;
proc contents data=sashelp.comet out=_descriptor(keep=name type length varnum label) noprint; run;
proc sort data=_descriptor; by varnum; run;
proc print data=_descriptor noobs; run;
proc print data=sashelp.comet(obs=5) noobs; run;
proc sql; select count(*) as Observations from sashelp.comet; quit;
proc contents data=sashelp.enso out=_descriptor(keep=name type length varnum label) noprint; run;
proc sort data=_descriptor; by varnum; run;
proc print data=_descriptor noobs; run;
proc print data=sashelp.enso(obs=5) noobs; run;
proc sql; select count(*) as Observations from sashelp.enso; quit;

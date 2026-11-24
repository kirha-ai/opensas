/* STAT-SASHELP-007: SASHELP example data — Hot-Spring Locations in the United States / Coal Seam Thickness Data / 1980 US Presidential Election Data
 * Source: S154 / Sashelp Data Sets / `Hot-Spring Locations in the United States` (PDF pp. 10922–10923); S154 / Sashelp Data Sets / `Coal Seam Thickness Data` (PDF pp. 10923–10924); S154 / Sashelp Data Sets / `1980 US Presidential Election Data` (PDF p. 10924).
 * Discriminates: Published SASHELP data availability, row counts, first observations and descriptors: springs, thick, vote1980
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

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

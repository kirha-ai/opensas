/* STAT-SASHELP-005: SASHELP example data — Fisher (1936) Iris Data / Junk Email Data / Leukemia Data Sets
 * Source: S154 / Sashelp Data Sets / `Fisher (1936) Iris Data` (PDF pp. 10912–10914); S154 / Sashelp Data Sets / `Junk Email Data` (PDF pp. 10914–10916); S154 / Sashelp Data Sets / `Leukemia Data Sets` (PDF pp. 10916–10918).
 * Discriminates: Published SASHELP data availability, row counts, first observations and descriptors: iris, junkmail, leutrain, leutest, margarin
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

proc contents data=sashelp.iris out=_descriptor(keep=name type length varnum label) noprint; run;
proc sort data=_descriptor; by varnum; run;
proc print data=_descriptor noobs; run;
proc print data=sashelp.iris(obs=5) noobs; run;
proc sql; select count(*) as Observations from sashelp.iris; quit;
proc contents data=sashelp.junkmail out=_descriptor(keep=name type length varnum label) noprint; run;
proc sort data=_descriptor; by varnum; run;
proc print data=_descriptor noobs; run;
proc print data=sashelp.junkmail(obs=5) noobs; run;
proc sql; select count(*) as Observations from sashelp.junkmail; quit;
proc contents data=sashelp.leutrain out=_descriptor(keep=name type length varnum label) noprint; run;
proc sort data=_descriptor; by varnum; run;
proc print data=_descriptor noobs; run;
proc print data=sashelp.leutrain(obs=5) noobs; run;
proc sql; select count(*) as Observations from sashelp.leutrain; quit;
proc contents data=sashelp.leutest out=_descriptor(keep=name type length varnum label) noprint; run;
proc sort data=_descriptor; by varnum; run;
proc print data=_descriptor noobs; run;
proc print data=sashelp.leutest(obs=5) noobs; run;
proc sql; select count(*) as Observations from sashelp.leutest; quit;
proc contents data=sashelp.margarin out=_descriptor(keep=name type length varnum label) noprint; run;
proc sort data=_descriptor; by varnum; run;
proc print data=_descriptor noobs; run;
proc print data=sashelp.margarin(obs=5) noobs; run;
proc sql; select count(*) as Observations from sashelp.margarin; quit;

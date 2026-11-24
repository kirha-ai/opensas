/* STAT-SASHELP-002: SASHELP example data — Body Mass Index for Men / Isopod Burrows Data / Bone Marrow Transplant Data
 * Source: S154 / Sashelp Data Sets / `Body Mass Index for Men` (PDF pp. 10902–10903); S154 / Sashelp Data Sets / `Isopod Burrows Data` (PDF pp. 10903–10905); S154 / Sashelp Data Sets / `Bone Marrow Transplant Data` (PDF pp. 10905–10906).
 * Discriminates: Published SASHELP data availability, row counts, first observations and descriptors: bmimen, burrows, bmt, bweight
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

proc contents data=sashelp.bmimen out=_descriptor(keep=name type length varnum label) noprint; run;
proc sort data=_descriptor; by varnum; run;
proc print data=_descriptor noobs; run;
proc print data=sashelp.bmimen(obs=5) noobs; run;
proc sql; select count(*) as Observations from sashelp.bmimen; quit;
proc contents data=sashelp.burrows out=_descriptor(keep=name type length varnum label) noprint; run;
proc sort data=_descriptor; by varnum; run;
proc print data=_descriptor noobs; run;
proc print data=sashelp.burrows(obs=5) noobs; run;
proc sql; select count(*) as Observations from sashelp.burrows; quit;
proc contents data=sashelp.bmt out=_descriptor(keep=name type length varnum label) noprint; run;
proc sort data=_descriptor; by varnum; run;
proc print data=_descriptor noobs; run;
proc print data=sashelp.bmt(obs=5) noobs; run;
proc sql; select count(*) as Observations from sashelp.bmt; quit;
proc contents data=sashelp.bweight out=_descriptor(keep=name type length varnum label) noprint; run;
proc sort data=_descriptor; by varnum; run;
proc print data=_descriptor noobs; run;
proc print data=sashelp.bweight(obs=5) noobs; run;
proc sql; select count(*) as Observations from sashelp.bweight; quit;

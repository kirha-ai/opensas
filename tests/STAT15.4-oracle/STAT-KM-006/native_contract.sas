/* STAT-KM-006: KM survival plot customization — Changing How the Censored Points Are Displayed / Adding a Y-Axis Reference Line / Adding Y-Axis Grid Lines / Changing the Homogeneity Test Inset
 * Source: S154 / Chapter 26 / `Changing How the Censored Points Are Displayed` (PDF pp. 958–959); S154 / Chapter 26 / `Adding a Y-Axis Reference Line` (PDF pp. 959–961); S154 / Chapter 26 / `Adding Y-Axis Grid Lines` (PDF pp. 961–962); S154 / Chapter 26 / `Changing the Homogeneity Test Inset` (PDF pp. 962–964).
 * Discriminates: Native Kaplan–Meier graph baseline and its template/ODS identity
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

options dlcreatedir; libname _gpath "%sysfunc(pathname(work))/stat_km_006"; libname _gpath clear;
ods listing gpath="%sysfunc(pathname(work))/stat_km_006";
ods graphics on / reset=all imagename="oracle" imagefmt=svg width=5in height=3in;
ods trace on;
data survival; input time status group $; datalines;
1 1 A
2 0 A
2 1 A
4 1 A
5 0 A
1 0 B
3 1 B
4 1 B
6 0 B
7 1 B
;
run;
proc lifetest data=survival plots=survival(cl test); time time*status(0); strata group; run;
ods trace off; ods graphics off;
data graph_files; length name $128; rc=filename('_gdir',"%sysfunc(pathname(work))/stat_km_006"); did=dopen('_gdir'); if did then do; do i=1 to dnum(did); name=dread(did,i); if lowcase(scan(name,-1,'.')) in ('svg','png') then output; end; rc=dclose(did); end; keep name; run;
proc print data=graph_files noobs; run;

/* STAT-GRAPHICS-009: ODS graphics — Graph Size and Resolution
 * Source: S154 / Chapter 24 / `Graph Size and Resolution` (PDF pp. 702–703).
 * Discriminates: ODS graphics enablement, explicit SVG format/size, graph identity and generated image file names
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

options dlcreatedir; libname _gpath "%sysfunc(pathname(work))/stat_graphics_009"; libname _gpath clear;
ods listing gpath="%sysfunc(pathname(work))/stat_graphics_009";
ods graphics on / reset=all imagename="oracle" imagefmt=svg width=5in height=3in;
ods trace on;
data sample;
 input x z y group $ weight freq;
 datalines;
1 1 4 A 1 1
2 1 6 A 2 1
3 2 7 A 1 2
4 1 9 A 1 1
5 3 13 A 2 1
6 2 12 A 1 1
7 4 17 B 1 1
8 3 19 B 2 2
9 5 20 B 1 1
10 3 23 B 1 1
11 5 25 B 2 1
12 4 24 B 1 1
;
run;
proc reg data=sample plots(only)=fitplot; model y=x; run; quit;
ods trace off; ods graphics off;
data graph_files; length name $128; rc=filename('_gdir',"%sysfunc(pathname(work))/stat_graphics_009"); did=dopen('_gdir'); if did then do; do i=1 to dnum(did); name=dread(did,i); if lowcase(scan(name,-1,'.')) in ('svg','png') then output; end; rc=dclose(did); end; keep name; run;
proc print data=graph_files noobs; run;

/* STAT-MDS-005: MDS — INITIAL= Data Set
 * Source: S154 / Chapter 81 / `INITIAL= Data Set` (PDF p. 6400).
 * Discriminates: Getting Started: MDS Procedure
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

title 'Analysis of Flying Mileages between Ten U.S. Cities';
ods graphics on;
proc mds data=sashelp.mileages level=absolute;
id city;
run;

/* STAT-MDS-001: MDS — Data input, variable roles, and basic options
 * Source: S154 / Chapter 81 / `PROC MDS Statement` (PDF pp. 6383–6393); S154 / Chapter 81 / `BY Statement` (PDF pp. 6393–6394); S154 / Chapter 81 / `ID Statement` (PDF p. 6394); S154 / Chapter 81 / `VAR Statement` (PDF p. 6395); S154 / Chapter 81 / `WEIGHT Statement` (PDF p. 6395); S154 / Chapter 81 / `Missing Values` (PDF p. 6400).
 * Discriminates: Two explicit BY groups contain identical inputs, exposing group boundaries and per-group results.
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
data _oracle_input; set sashelp.mileages; do _oracle_by=1 to 2; output; end; run;
proc sort data=_oracle_input; by _oracle_by; run;
proc mds data=_oracle_input level=absolute;
by _oracle_by;
id city;
run;

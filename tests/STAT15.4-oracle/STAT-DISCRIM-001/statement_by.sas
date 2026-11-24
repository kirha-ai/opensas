/* STAT-DISCRIM-001: DISCRIM — Data input, variable roles, and basic options
 * Source: S154 / Chapter 42 / `PROC DISCRIM Statement` (PDF pp. 2652–2660); S154 / Chapter 42 / `BY Statement` (PDF pp. 2660–2661); S154 / Chapter 42 / `CLASS Statement` (PDF p. 2661); S154 / Chapter 42 / `FREQ Statement` (PDF pp. 2661–2662); S154 / Chapter 42 / `ID Statement` (PDF p. 2662); S154 / Chapter 42 / `VAR Statement` (PDF pp. 2663–2664); S154 / Chapter 42 / `WEIGHT Statement` (PDF p. 2664); S154 / Chapter 42 / `Missing Values` (PDF p. 2664); S154 / Chapter 42 / `Input Data Sets` (PDF pp. 2675–2676).
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

title 'Fish Measurement Data';
data _oracle_input; set sashelp.fish; do _oracle_by=1 to 2; output; end; run;
proc sort data=_oracle_input; by _oracle_by; run;
proc discrim data=_oracle_input;
by _oracle_by;
class Species;
run;

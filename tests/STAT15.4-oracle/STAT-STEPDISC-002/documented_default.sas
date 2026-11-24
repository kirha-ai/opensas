/* STAT-STEPDISC-002: STEPDISC — Stepwise selection of discriminant variables
 * Source: S154 / Chapter 117 / `Getting Started: STEPDISC Procedure` (PDF pp. 9555–9559); S154 / Chapter 117 / `Overview: STEPDISC Procedure` (PDF pp. 9553–9555).
 * Discriminates: Getting Started: STEPDISC Procedure
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
proc stepdisc data=sashelp.fish;
class Species;
run;

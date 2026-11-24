/* STAT-DISCRIM-006: DISCRIM — Saving and Using Calibration Information
 * Source: S154 / Chapter 42 / `Saving and Using Calibration Information` (PDF pp. 2674–2675).
 * Discriminates: Getting Started: DISCRIM Procedure
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
proc discrim data=sashelp.fish;
class Species;
run;

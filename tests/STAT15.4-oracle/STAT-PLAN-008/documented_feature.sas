/* STAT-PLAN-008: PLAN — Official examples and feature integration regression
 * Source: S154 / Chapter 93 / `Examples: PLAN Procedure` (PDF pp. 7600–7616).
 * Discriminates: Example 93.1: A Split-Plot Design
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

title 'Split Plot Design';
proc plan seed=37277;
factors Block=3 ordered a=4 b=2;
run;

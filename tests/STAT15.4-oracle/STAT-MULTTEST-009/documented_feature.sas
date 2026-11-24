/* STAT-MULTTEST-009: MULTTEST — Official examples and feature integration regression
 * Source: S154 / Chapter 86 / `Examples: MULTTEST Procedure` (PDF pp. 6936–6960).
 * Discriminates: Example 86.5: Inputting Raw p-Values
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data a;
input Test$ Raw_P @@;
datalines;
test01 0.28282 test02 0.30688 test03 0.71022
test04 0.77175 test05 0.78180 test06 0.88581
test07 0.54685 test08 0.84978 test09 0.24228
test10 0.58977 test11 0.03498 test12 0.41607
test13 0.31631 test14 0.05254 test15 0.45061
test16 0.75758 test17 0.12496 test18 0.49485
test19 0.21572 test20 0.50505 test21 0.94372
test22 0.81260 test23 0.77596 test24 0.36889
;
proc multtest inpvalues=a holm hoc fdr;
run;

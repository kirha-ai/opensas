/* STAT-DISCRIM-010: DISCRIM — Official examples and feature integration regression
 * Source: S154 / Chapter 42 / `Examples: DISCRIM Procedure` (PDF pp. 2687–2736).
 * Discriminates: Example 42.3: Normal-Theory Discriminant Analysis of Iris Data
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

title 'Discriminant Analysis of Fisher (1936) Iris Data';
title2 'Using Quadratic Discriminant Function';
proc discrim data=sashelp.iris outstat=irisstat
wcov pcov method=normal pool=test
distance anova manova listerr crosslisterr;
class Species;
var SepalLength SepalWidth PetalLength PetalWidth;
run;
proc print data=irisstat;
title2 'Output Discriminant Statistics';
run;

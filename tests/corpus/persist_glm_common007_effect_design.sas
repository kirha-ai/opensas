/* STAT-COMMON-007: Design matrices for main effects, interactions, and nesting
 * Source: S154 / Chapter 20 / `GLM Parameterization of Classification Variables and Effects` (PDF pp. 414–418).
 * Discriminates: Main, interaction, continuous-by-class and intercept design columns
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

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
data design_input; set sample; h=mod(_n_,3); run;
proc glmmod data=design_input outdesign=matrix outparm=columns noprint;
 class group h; model y=group h group*h x group*x; run;
proc print data=columns noobs; run;
proc print data=matrix noobs; run;

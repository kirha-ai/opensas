/* STAT-COMMON-017: Ranks, ties, and nonparametric test interfaces
 * Source: S154 / Chapter 17 / `Introduction to Nonparametric Analysis` (PDF pp. 295–302).
 * Discriminates: Tied ranks and exact versus asymptotic rank inference
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
 input x y group $ freq weight;
 datalines;
43 40 A 1 1
90 84 A 2 1
84 88 A 1 2
87 80 A 1 1
116 110 A 1 1
95 91 A 1 2
86 79 B 1 1
99 101 B 2 1
93 90 B 1 2
92 85 B 1 1
121 115 B 1 1
71 72 B 1 2
;
run;
data ranks; set sample; x=round(x,10); run;
proc npar1way data=ranks wilcoxon; class group; var x; exact wilcoxon; run;

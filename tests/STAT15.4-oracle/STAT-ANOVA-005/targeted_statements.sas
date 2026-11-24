/* STAT-ANOVA-005: ANOVA — REPEATED
 * Source: S154 / Chapter 29 / `REPEATED Statement` (PDF pp. 1129–1134).
 * Discriminates: Explicit REPEATED statement behavior on seeded synthetic inputs.
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
call streaminit(314159);
do block=1 to 4; do group=1 to 2; do replicate=1 to 5;
y=10+block+2*group+rand('normal');
y1=y+rand('normal'); y2=y+1+rand('normal'); y3=y+2+rand('normal');
output;
end; end; end;
run;
proc anova data=sample; class group; model y1-y3=group; repeated time 3 (0 1 2) polynomial / summary; run; quit;

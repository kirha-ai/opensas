/* STAT-ANOVA-004: ANOVA — ABSORB / Using PROC ANOVA Interactively / Computational Method
 * Source: S154 / Chapter 29 / `ABSORB Statement` (PDF p. 1117); S154 / Chapter 29 / `Using PROC ANOVA Interactively` (PDF p. 1138); S154 / Chapter 29 / `Computational Method` (PDF p. 1140).
 * Discriminates: Explicit ABSORB statement behavior on seeded synthetic inputs.
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
proc anova data=sample; absorb block; class group; model y=group; run; quit;

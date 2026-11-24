/* STAT-INBREED-002: INBREED — Inbreeding coefficient and relationship recursions
 * Source: S154 / Chapter 71 / `Getting Started: INBREED Procedure` (PDF pp. 5270–5274); S154 / Chapter 71 / `Overview: INBREED Procedure` (PDF p. 5270).
 * Discriminates: Documented default analysis with explicit complete public or synthetic inputs
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data pedigree; input animal $ sire $ dam $; datalines;
A . .
B . .
C A B
D A B
E C D
;
run;
proc inbreed data=pedigree covar matrix; var animal sire dam; run;

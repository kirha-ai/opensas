/* STAT-TREE-001: TREE — Data input, variable roles, and basic options
 * Source: S154 / Chapter 127 / `PROC TREE Statement` (PDF pp. 10575–10581); S154 / Chapter 127 / `BY Statement` (PDF p. 10581); S154 / Chapter 127 / `COPY Statement` (PDF p. 10581); S154 / Chapter 127 / `FREQ Statement` (PDF pp. 10581–10582); S154 / Chapter 127 / `ID Statement` (PDF p. 10582); S154 / Chapter 127 / `Missing Values` (PDF p. 10583).
 * Discriminates: Two explicit BY groups contain identical inputs, exposing group boundaries and per-group results.
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

proc cluster data=sashelp.iris method=ward outtree=tree noprint; var SepalLength SepalWidth PetalLength PetalWidth; run;
data _oracle_input; set tree; do _oracle_by=1 to 2; output; end; run;
proc sort data=_oracle_input; by _oracle_by; run;
proc tree data=_oracle_input nclusters=3 out=members noprint;
by _oracle_by; run;
proc print data=members(obs=12) noobs; run;

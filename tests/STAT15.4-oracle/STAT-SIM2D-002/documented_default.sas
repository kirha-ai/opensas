/* STAT-SIM2D-002: SIM2D — Conditional/unconditional two-dimensional spatial random field simulation
 * Source: S154 / Chapter 112 / `Getting Started: SIM2D Procedure` (PDF pp. 9307–9314); S154 / Chapter 112 / `Overview: SIM2D Procedure` (PDF pp. 9306–9307).
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

proc sim2d data=sashelp.thick outsim=sim; coordinates xc=East yc=North; simulate var=Thick numreal=2 seed=79931 scale=7.4599 range=30.1111 nugget=1e-8 form=gauss; mean 40.1173; grid x=0 to 20 by 10 y=0 to 20 by 10; run;
proc print data=sim noobs; run;

/* STAT-CAUSALTRT-006: CAUSALTRT — BOOTSTRAP
 * Source: S154 / Chapter 39 / `BOOTSTRAP Statement` (PDF pp. 2445–2448).
 * Discriminates: Seeded 50-replicate bootstrap with normal confidence intervals.
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data trial; call streaminit(193); do id=1 to 200; age=20+mod(id*7,45); bmi=20+mod(id,12); gender=mod(id,2); drug=rand('bernoulli',1/(1+exp(-(-2+age*.03+gender*.3)))); outcome=rand('bernoulli',1/(1+exp(-(-1+drug*.6+age*.01)))); output; end; run;
proc causaltrt data=trial method=ipwr; class gender; psmodel drug(ref='0')=age bmi gender; model outcome(ref='0') /dist=bin; bootstrap nboot=50 seed=314159 bootci(normal);
run;

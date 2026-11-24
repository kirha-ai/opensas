/* STAT-IRT-002: IRT — Default likelihood estimation for item response models
 * Source: S154 / Chapter 72 / `Getting Started: IRT Procedure` (PDF pp. 5297–5301); S154 / Chapter 72 / `Overview: IRT Procedure` (PDF pp. 5296–5297).
 * Discriminates: Small synthetic/public-input default model adapted to the documented Getting Started procedure
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data responses; call streaminit(329); array item[5] item1-item5; do subject=1 to 150; theta=rand('normal'); do k=1 to 5; item[k]=rand('bernoulli',1/(1+exp(-(theta-(k-3)/2)))); end; output; end; keep item1-item5; run;
proc irt data=responses; var item1-item5; run;

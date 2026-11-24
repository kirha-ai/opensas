/* STAT-PRINQUAL-006: PRINQUAL — Character OPSCORE Variables / REITERATE Option Usage / Passive Observations
 * Source: S154 / Chapter 99 / `Character OPSCORE Variables` (PDF p. 8068); S154 / Chapter 99 / `REITERATE Option Usage` (PDF pp. 8068–8069); S154 / Chapter 99 / `Passive Observations` (PDF pp. 8069–8070).
 * Discriminates: Verified default procedure context
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

proc prinqual data=sashelp.class out=scaled;
transform identity(height weight age);
run;
proc print data=scaled(obs=5) noobs;
run;

/* STAT-LIFETEST-008: LIFETEST — Output Data Sets
 * Source: S154 / Chapter 77 / `Output Data Sets` (PDF pp. 5692–5695).
 * Discriminates: Getting Started: LIFETEST Procedure
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

proc format; value Rx 1='Drug X' 0='Placebo'; run;
data exposed;
input Days Status Treatment Sex $ @@;
format Treatment Rx.;
datalines;
179 1 1 F 378 0 1 M
256 1 1 F 355 1 1 M
262 1 1 M 319 1 1 M
256 1 1 F 256 1 1 M
255 1 1 M 171 1 1 F
224 0 1 F 325 1 1 M
225 1 1 F 325 1 1 M
287 1 1 M 217 1 1 F
319 1 1 M 255 1 1 F
264 1 1 M 256 1 1 F
237 0 0 F 291 1 0 M
156 1 0 F 323 1 0 M
270 1 0 M 253 1 0 M
257 1 0 M 206 1 0 F
242 1 0 M 206 1 0 F
157 1 0 F 237 1 0 M
249 1 0 M 211 1 0 F
180 1 0 F 229 1 0 F
226 1 0 F 234 1 0 F
268 0 0 M 209 1 0 F
;
ods graphics on;
proc lifetest data=Exposed plots=(survival(atrisk) logsurv);
time Days*Status(0);
strata Treatment;
run;
ods graphics off;
proc lifetest data=Exposed notable;
time Days*Status(0);
strata Sex / group=Treatment;
run;
proc lifetest data=Exposed notable;
time Days*Status(0);
test Treatment;
run;

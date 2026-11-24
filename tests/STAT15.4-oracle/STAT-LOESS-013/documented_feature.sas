/* STAT-LOESS-013: LOESS — Official examples and feature integration regression
 * Source: S154 / Chapter 78 / `Examples: LOESS Procedure` (PDF pp. 5796–5821).
 * Discriminates: Example 78.4: El Niño Southern Oscillation
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

proc sgplot data=sashelp.ENSO;
scatter y=Pressure x=Month;
run;
ods graphics on;
proc loess data=sashelp.ENSO plots=residuals(smooth);
model Pressure=Month;
run;
proc loess data=sashelp.ENSO;
model Pressure=Month/select=AICC(global);
run;
proc loess data=sashelp.ENSO;
model Pressure=Month/select=AICC(range(0.03,0.2));
run;
proc loess data=sashelp.ENSO plots=residuals(smooth);
model Pressure=Month/select=AICC(presearch);
run;
ods graphics off;
run;
quit;

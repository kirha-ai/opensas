/* STAT-SPP-012: SPP — Output Data Sets
 * Source: S154 / Chapter 114 / `Output Data Sets` (PDF pp. 9423–9425).
 * Discriminates: Getting Started: SPP Procedure
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

ods graphics on;
proc spp data=sashelp.bei plots(equate)=(trends observations);
process trees = (x, y /area=(0,0,1000,500) Event=Trees);
trend grad = field(x,y, gradient);
trend elev = field(x,y, elevation);
run;
proc spp data=sashelp.bei plots(equate)=(residual intensity);
process trees = (x,y /area=(0,0,1000,500) event=Trees);
trend elev = field(x,y,elevation);
trend grad = field(x,y,gradient);
model trees = elev grad / grid(64,64) residual(B=70) ;
run;

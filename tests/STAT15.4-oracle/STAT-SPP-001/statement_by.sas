/* STAT-SPP-001: SPP — Data input, variable roles, and basic options
 * Source: S154 / Chapter 114 / `PROC SPP Statement` (PDF pp. 9391–9398); S154 / Chapter 114 / `BY Statement` (PDF p. 9398).
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

ods graphics on;
data _oracle_input; set sashelp.bei; do _oracle_by=1 to 2; output; end; run;
proc sort data=_oracle_input; by _oracle_by; run;
proc spp data=_oracle_input plots(equate)=(trends observations);
by _oracle_by;
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

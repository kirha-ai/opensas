/* STAT-HPCANDISC-001: HPCANDISC — Data input, variable roles, and basic options
 * Source: S154 / Chapter 57 / `PROC HPCANDISC Statement` (PDF pp. 4483–4487); S154 / Chapter 57 / `BY Statement` (PDF p. 4487); S154 / Chapter 57 / `CLASS Statement` (PDF p. 4487); S154 / Chapter 57 / `FREQ Statement` (PDF pp. 4487–4488); S154 / Chapter 57 / `ID Statement` (PDF p. 4488); S154 / Chapter 57 / `VAR Statement` (PDF p. 4488); S154 / Chapter 57 / `WEIGHT Statement` (PDF pp. 4488–4489); S154 / Chapter 57 / `Missing Values` (PDF p. 4489).
 * Discriminates: Verified default procedure context; explicit statements: CLASS, ID, VAR, WEIGHT
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

title 'Fish Measurement Data';
proc hpcandisc data=sashelp.fish ncan=3 out=outcan;
ods exclude tstruc bstruc pstruc tcoef pcoef;
id Species;
class Species;
var Weight Length1 Length2 Length3 Height Width;
run;
proc template;
define statgraph scatter;
begingraph;
entrytitle 'Fish Measurement Data';
layout overlayequated / equatetype=fit
xaxisopts=(label='Canonical Variable 1')
yaxisopts=(label='Canonical Variable 2');
scatterplot x=Can1 y=Can2 / group=species name='fish';
layout gridded / autoalign=(topright);
discretelegend 'fish' / border=false opaque=false;
endlayout;
endlayout;
endgraph;
end;
run;
proc sgrender data=outcan template=scatter;
run;

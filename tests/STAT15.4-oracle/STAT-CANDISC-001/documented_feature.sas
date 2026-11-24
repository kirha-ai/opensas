/* STAT-CANDISC-001: CANDISC — Data input, variable roles, and basic options
 * Source: S154 / Chapter 35 / `PROC CANDISC Statement` (PDF pp. 2156–2159); S154 / Chapter 35 / `BY Statement` (PDF p. 2159); S154 / Chapter 35 / `CLASS Statement` (PDF pp. 2159–2160); S154 / Chapter 35 / `FREQ Statement` (PDF p. 2160); S154 / Chapter 35 / `VAR Statement` (PDF p. 2160); S154 / Chapter 35 / `WEIGHT Statement` (PDF pp. 2160–2161); S154 / Chapter 35 / `Missing Values` (PDF p. 2161); S154 / Chapter 35 / `Input Data Set` (PDF pp. 2162–2163).
 * Discriminates: Verified default procedure context; explicit statements: CLASS, VAR, WEIGHT
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
proc candisc data=sashelp.fish ncan=3 out=outcan;
ods exclude tstruc bstruc pstruc tcoef pcoef;
class Species;
var Weight Length1 Length2 Length3 Height Width;
run;
proc template;
define statgraph scatter;
begingraph / attrpriority=none;
entrytitle 'Fish Measurement Data';
layout overlayequated / equatetype=fit
xaxisopts=(label='Canonical Variable 1')
yaxisopts=(label='Canonical Variable 2');
scatterplot x=Can1 y=Can2 / group=species name='fish'
markerattrs=(size=3px);
layout gridded / autoalign=(topright);
discretelegend 'fish' / border=false opaque=false;
endlayout;
endlayout;
endgraph;
end;
run;
proc sgrender data=outcan template=scatter;
run;

/* STAT-HPCANDISC-003: HPCANDISC — General Formulas
 * Source: S154 / Chapter 57 / `General Formulas` (PDF pp. 4489–4490).
 * Discriminates: Example 57.1: Analyzing Iris Data with PROC HPCANDISC
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

title 'Fisher (1936) Iris Data';
proc hpcandisc data=sashelp.iris out=outcan distance anova;
id Species;
class Species;
var SepalLength SepalWidth PetalLength PetalWidth;
run;
proc template;
define statgraph scatter;
begingraph;
entrytitle 'Fisher (1936) Iris Data';
layout overlayequated / equatetype=fit
xaxisopts=(label='Canonical Variable 1')
yaxisopts=(label='Canonical Variable 2');
scatterplot x=Can1 y=Can2 / group=species name='iris';
layout gridded / autoalign=(topleft);
discretelegend 'iris' / border=false opaque=false;
endlayout;
endlayout;
endgraph;
end;
run;
proc sgrender data=outcan template=scatter;
run;

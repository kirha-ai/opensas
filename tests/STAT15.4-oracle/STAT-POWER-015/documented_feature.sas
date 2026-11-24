/* STAT-POWER-015: POWER — Analyses in the TWOSAMPLESURVIVAL / Analyses in the TWOSAMPLEWILCOXON
 * Source: S154 / Chapter 96 / `Analyses in the TWOSAMPLESURVIVAL Statement` (PDF pp. 7912–7915); S154 / Chapter 96 / `Analyses in the TWOSAMPLEWILCOXON Statement` (PDF pp. 7915–7917).
 * Discriminates: Example 96.2: The Sawtooth Power Function in Proportion Analyses
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

proc power;
onesamplefreq test=z method=normal
sides = 1
alpha = 0.05
nullproportion = 0.3
proportion = 0.2
ntotal = .
power = 0.8;
run;
proc power;
onesamplefreq test=adjz method=normal
sides = 1
alpha = 0.05
nullproportion = 0.3
proportion = 0.2
ntotal = .
power = 0.8;
run;
ods graphics on;
proc power plotonly;
onesamplefreq test=exact
sides = 1
alpha = 0.05
nullproportion = 0.3
proportion = 0.2
ntotal = 119
power = .;
plot x=n min=110 max=140 step=1
yopts=(ref=.8) xopts=(ref=119 129);
run;
proc power plotonly;
onesamplefreq test=exact
sides = 1
alpha = 0.05
nullproportion = 0.3
proportion = 0.18 0.2 0.22
ntotal = 119
power = .;
plot x=n min=110 max=140 step=1
yopts=(ref=.8) xopts=(ref=119 129);
run;
proc power plotonly;
ods output plotcontent=PlotData;
onesamplefreq test=exact
sides = 1
alpha = 0.05
nullproportion = 0.3
proportion = 0.2
ntotal = 119
power = .;
plot x=n min=110 max=140 step=1
yopts=(ref=.8) xopts=(ref=119 129);
run;
proc print data=PlotData;
var NTotal LowerCritVal Alpha Power;
run;
proc power plotonly;
onesamplefreq test=exact
sides = 1
alpha = 0.05
nullproportion = 0.2
proportion = 0.3
ntotal = 119
power = .;
plot x=n min=110 max=140 step=1;
run;
proc power plotonly;
onesamplefreq test=exact
sides = 2
alpha = 0.2
nullproportion = 0.1
proportion = 0.09
ntotal = 10
power = .;
plot x=n min=2 max=100 step=1;
run;
ods graphics off;
run;
quit;

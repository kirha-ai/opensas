/* STAT-MODECLUS-007: MODECLUS — Official examples and feature integration regression
 * Source: S154 / Chapter 85 / `Examples: MODECLUS Procedure` (PDF pp. 6844–6888).
 * Discriminates: Example 85.3: Cluster Analysis with Significance Tests
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

title 'Modeclus Analysis with the JOIN= option';
title2 'A Normal Cluster Surrounded by a Ring Cluster';
data circle;
keep x y;
c=1;
do n=1 to 30;
x=rannor(5);
y=rannor(5);
output;
end;
c=2;
do n=1 to 300;
x=rannor(5);
y=rannor(5);
z=rannor(5)+8;
l=z/sqrt(x**2+y**2);
x=x*l;
y=y*l;
output;
end;
run;
proc modeclus data=circle m=1 r=1 to 3.5 by .25 join=20 short;
run;
proc modeclus data=circle m=1 r=2.5 join out=out;
run;
proc sgplot data=out noautolegend;
yaxis values=(-10 to 10 by 5);
xaxis values=(-15 to 15 by 5);
scatter y=y x=x / group=cluster Markerchar=cluster;
by _NJOIN_;
run;

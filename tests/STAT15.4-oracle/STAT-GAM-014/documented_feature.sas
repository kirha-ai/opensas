/* STAT-GAM-014: GAM — Official examples and feature integration regression
 * Source: S154 / Chapter 48 / `Examples: GAM Procedure` (PDF pp. 3323–3345).
 * Discriminates: Example 48.2: Poisson Regression Analysis of Component Reliability
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

title 'Analysis of Component Reliability';
data equip;
input year month removals @@;
datalines;
1987 1 2 1987 2 4 1987 3 3
1987 4 3 1987 5 3 1987 6 8
1987 7 2 1987 8 6 1987 9 3
1987 10 9 1987 11 4 1987 12 10
1988 1 4 1988 2 6 1988 3 4
1988 4 4 1988 5 3 1988 6 5
1988 7 3 1988 8 4 1988 9 5
1988 10 3 1988 11 6 1988 12 3
1989 1 2 1989 2 6 1989 3 1
1989 4 5 1989 5 5 1989 6 4
1989 7 2 1989 8 2 1989 9 2
1989 10 5 1989 11 1 1989 12 10
1990 1 3 1990 2 8 1990 3 12
1990 4 7 1990 5 3 1990 6 2
1990 7 4 1990 8 3 1990 9 0
1990 10 6 1990 11 6 1990 12 6
;
title2 'Two-way model';
proc genmod data=equip;
class year month;
model removals=year month / dist=Poisson link=log type3;
run;
title2 'One-way model';
proc gam data=equip;
class month;
model removals=param(month) / dist=Poisson;
output out=est p;
run;
proc sort data=est;
by month;
run;
proc sgplot data=est;
title "Predicted Seasonal Trend";
yaxis label="Number of Removals";
xaxis integer values=(1 to 12);
scatter x=Month y=Removals / name="points"
legendLabel="Removals";
series x=Month y=p_Removals / name="line"
legendLabel="Predicted Removals"
lineattrs = GRAPHFIT;
discretelegend "points" "line";
run;
title 'Analysis of Component Reliability';
title2 'Spline model';
proc gam data=equip;
model removals=spline(month) / dist=Poisson method=gcv;
run;
ods graphics on;
proc gam data=equip plots=components(clm);
model removals=spline(month) / dist=Poisson method=gcv;
run;
ods graphics off;
run;
quit;

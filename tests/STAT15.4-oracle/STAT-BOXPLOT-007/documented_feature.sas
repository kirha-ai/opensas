/* STAT-BOXPLOT-007: BOXPLOT — Official examples and feature integration regression
 * Source: S154 / Chapter 32 / `Examples: BOXPLOT Procedure` (PDF pp. 1429–1442).
 * Discriminates: Example 32.5: Creating Box-and-Whiskers Plots with Varying Widths
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data Times2;
label Delay = 'Delay in Minutes';
informat Day date7. ;
format Day date7. ;
input Day @ ;
do Flight=1 to 25;
input Delay @ ;
output;
end;
datalines;
01MAR90 12 4 2 2 15 8 0 11 0 0
0 12 3 . 2 3 5 0 6 25
7 4 9 5 10
02MAR90 1 . 3 . 0 1 5 0 . .
1 5 7 . 7 2 2 16 2 1
3 1 31 . 0
03MAR90 6 8 4 2 3 2 7 6 11 3
2 7 0 1 10 2 5 12 8 6
2 7 2 4 5
04MAR90 12 6 9 0 15 7 1 1 0 2
5 6 5 14 7 21 8 1 14 3
11 0 1 11 7
05MAR90 2 1 0 4 . 6 2 2 1 4
1 11 . 1 0 . 5 5 . 2
3 6 6 4 0
06MAR90 8 6 5 2 9 7 4 2 5 1
2 2 4 2 5 1 3 9 7 8
1 0 4 26 27
07MAR90 9 6 6 2 7 8 . . 10 8
0 2 4 3 . . . 7 . 6
4 0 . . .
08MAR90 1 6 6 2 8 8 5 3 5 0
8 2 4 2 5 1 6 4 5 10
2 0 4 1 1
;
title 'Analysis of Airline Departure Delays';
title2 'Using the BOXWIDTHSCALE= Option';
proc boxplot data=Times2;
plot Delay*Day /
boxstyle = schematic
odstitle = title
odstitle2 = title2
outbox = DelaySummary
boxwidthscale = 1
nohlabel
bwslegend;
run;

/* Numerical companion to the graph: native OUTBOX rows. */
proc print data=DelaySummary noobs; format _numeric_ best16.; run;

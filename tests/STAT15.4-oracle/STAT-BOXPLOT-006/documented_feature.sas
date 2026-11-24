/* STAT-BOXPLOT-006: BOXPLOT — Styles of Box Plots / Positioning Insets / Clipping Extreme Values / ODS Graphics
 * Source: S154 / Chapter 32 / `Styles of Box Plots` (PDF pp. 1414–1415); S154 / Chapter 32 / `Positioning Insets` (PDF pp. 1418–1423); S154 / Chapter 32 / `Clipping Extreme Values` (PDF pp. 1425–1429); S154 / Chapter 32 / `ODS Graphics` (PDF p. 1429).
 * Discriminates: Example 32.3: Creating Various Styles of Box-and-Whiskers Plots
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
ods trace on;
ods trace on;
data Times;
informat Day date7. ;
format Day date7. ;
input Day @ ;
do Flight=1 to 25;
input Delay @ ;
output;
end;
datalines;
16DEC88 4 12 2 2 18 5 6 21 0 0
0 14 3 . 2 3 5 0 6 19
7 4 9 5 10
17DEC88 1 10 3 3 0 1 5 0 . .
1 5 7 1 7 2 2 16 2 1
3 1 31 5 0
18DEC88 7 8 4 2 3 2 7 6 11 3
2 7 0 1 10 2 3 12 8 6
2 7 2 4 5
19DEC88 15 6 9 0 15 7 1 1 0 2
5 6 5 14 7 20 8 1 14 3
10 0 1 11 7
20DEC88 2 1 0 4 4 6 2 2 1 4
1 11 . 1 0 6 5 5 4 2
2 6 6 4 0
21DEC88 2 6 6 2 7 7 5 2 5 0
9 2 4 2 5 1 4 7 5 6
5 0 4 36 28
22DEC88 3 7 22 1 11 11 39 46 7 33
19 21 1 3 43 23 9 0 17 35
50 0 2 1 0
23DEC88 6 11 8 35 36 19 21 . . 4
6 63 35 3 12 34 9 0 46 0
0 36 3 0 14
24DEC88 13 2 10 4 5 22 21 44 66 13
8 3 4 27 2 12 17 22 19 36
9 72 2 4 4
25DEC88 4 33 35 0 11 11 10 28 34 3
24 6 17 0 8 5 7 19 9 7
21 17 17 2 6
26DEC88 3 8 8 2 7 7 8 2 5 9
2 8 2 10 16 9 5 14 15 1
12 2 2 14 18
;
run;
data Times; set Times; length Reason $16; if Delay>30 then Reason='Long delay'; else Reason='Routine'; run;
ods graphics on;
title 'Analysis of Airline Departure Delays';
title2 'BOXSTYLE=SKELETAL';
proc boxplot data=Times;
plot Delay*Day /
boxstyle = skeletal
odstitle = title
nohlabel;
label Delay = 'Delay in Minutes';
run;
title 'Analysis of Airline Departure Delays';
title2 'BOXSTYLE=SCHEMATIC';
proc boxplot data=Times;
plot Delay*Day /
boxstyle = schematic
odstitle = title
nohlabel;
label Delay = 'Delay in Minutes';
run;
title 'Analysis of Airline Departure Delays';
title2 'BOXSTYLE=SCHEMATICID';
proc boxplot data=Times;
plot Delay*Day /
boxstyle = schematicid
odstitle = title
odstitle2 = title2
nohlabel;
id Reason;
label Delay = 'Delay in Minutes';
run;
title 'Analysis of Airline Departure Delays';
title2 'BOXSTYLE=SCHEMATICIDFAR';
proc boxplot data=Times;
plot Delay*Day /
boxstyle = schematicidfar
odstitle = title
odstitle2 = title2
nohlabel;
id Reason;
label Delay = 'Delay in Minutes';
run;
ods trace off;
ods trace off;
ods graphics off;

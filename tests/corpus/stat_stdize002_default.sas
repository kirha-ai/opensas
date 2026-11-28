/* STAT-STDIZE-002: the documented default path of PROC STDIZE (no METHOD=,
 * so METHOD=STD: location = mean, scale = standard deviation, VARDEF=DF).
 *
 * Part 1 - Getting Started (S154 Chapter 115, PDF pp. 9449-9455): the High
 * School Scores sample data published there, BY Type, PSTAT. The expected
 * PSTAT values are the published Figure 115.3 (rural 167.050000 / 41.956713 /
 * 20, urban 153.300000 / 30.066768 / 20) and Figure 115.7 after removing the
 * outlier (urban 158.000000 / 22.088207 / 19). The standardized outlier
 * (obs 23, total = 64) is hand arithmetic: (64 - 153.3) / 30.066767806 =
 * -2.97005653.
 *
 * Part 2 - a smaller invented case with an independent manual calculation,
 * no VAR statement (every numeric variable is analysed):
 *   x = 2,4,4,4,5,5,7,9: mean 5, CSS 32, std sqrt(32/7) = 2.138090,
 *       standardized -1.40312152, -0.46770717 (x3), 0, 0, 0.93541435,
 *       1.87082869;
 *   y = 3,.,5,7,9,.,11,13: N 6, mean 8, CSS 70, std sqrt(14) = 3.741657,
 *       standardized -1.33630621, ., -0.80178373, -0.26726124, 0.26726124,
 *       ., 0.80178373, 1.33630621 (missing values stay missing).
 * Precision: PSTAT values are checked at their displayed 6 decimals; OUT=
 * values at 8 decimals (absolute error < 5e-9 of the exact hand values).
 */
options nodate nonumber nocenter linesize=160;
data TotalScores;
title 'High School Scores Data';
input id Type $ total @@;
datalines;
1 rural 135 2 rural 125 3 rural 223 4 rural 224 5 rural 133
6 rural 253 7 rural 144 8 rural 193 9 rural 152 10 rural 178
11 rural 120 12 rural 180 13 rural 154 14 rural 184 15 rural 187
16 rural 111 17 rural 190 18 rural 128 19 rural 110 20 rural 217
21 urban 192 22 urban 186 23 urban 64 24 urban 159 25 urban 133
26 urban 163 27 urban 130 28 urban 163 29 urban 189 30 urban 144
31 urban 154 32 urban 198 33 urban 150 34 urban 151 35 urban 152
36 urban 151 37 urban 127 38 urban 167 39 urban 170 40 urban 123
;
proc stdize data=totalscores out=gs pstat;
title2 'Default METHOD';
var total;
by Type;
run;
data NoOutlier;
set totalscores;
if (total = 64) then delete;
run;
proc stdize data=NoOutlier method=std pstat;
title2 'After Removing Outlier, METHOD=STD';
var total;
by Type;
run;
title;
proc print data=gs noobs;
where id = 23;
format total 12.8;
run;
data small;
input x y;
datalines;
2 3
4 .
4 5
4 7
5 9
5 .
7 11
9 13
;
proc stdize data=small out=small_std pstat;
run;
proc print data=small_std noobs;
format x y 12.8;
run;

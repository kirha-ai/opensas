/* STAT-GLMSELECT-001: PROC GLMSELECT default stepwise path (SELECT=SBC,
 * STOP=SBC) with DETAILS=ALL STATS=ALL: model information, observation
 * counts with a missing response and a missing regressor, CLASS levels,
 * dimensions, every step, the selection summary, stop details and the
 * selected model, repeated for two BY groups. Layout follows the SAS/STAT 15.4 reference listing; the
 * numbers come from an independent exact rational least-squares calculation
 * and the documented criteria formulas. Invented data.
 */
options linesize=160;
data trial;
input grp $ x1-x12 y;
datalines;
East 20 13 3 7 18 14 14 6 16 10 4 1 9.33
West 4 12 1 9 12 3 14 8 19 12 18 20 11.33
West 12 15 10 2 1 6 9 2 3 5 12 8 12.59
East 18 18 5 10 18 7 5 11 2 0 11 18 9.85
East 17 9 18 14 17 10 7 2 18 4 4 13 .
East 18 15 20 13 11 3 8 8 15 1 20 2 17.95
East 15 6 13 17 6 13 6 10 12 16 5 3 11.61
East 19 10 19 16 8 11 19 16 11 19 6 7 18.59
East 12 19 3 19 10 4 9 18 8 4 18 14 10.99
West 19 9 0 7 11 2 3 4 20 2 12 13 6.42
West 19 13 12 9 13 14 15 11 13 9 4 7 14.45
East 8 5 5 8 1 2 5 4 14 15 1 19 8.55
East 4 7 0 14 4 2 11 16 5 5 12 4 8.44
West 15 5 2 11 7 4 16 17 7 8 9 2 10.24
East 17 7 18 12 11 9 9 8 2 2 17 11 17.37
East 5 9 6 9 17 20 7 6 7 4 14 6 11.55
West 13 2 6 10 14 11 3 17 16 19 3 8 8.77
East 9 17 1 14 . 10 19 11 8 1 8 12 10.98
West 2 8 4 9 13 6 20 18 5 11 4 9 10.93
West 2 20 15 3 1 14 3 1 20 19 5 11 11.7
West 15 2 17 7 9 10 17 0 8 0 16 16 18.72
East 0 13 10 1 19 11 14 18 4 20 2 15 12.76
West 5 11 3 12 0 0 17 7 6 4 15 12 12.86
East 13 3 5 10 10 19 15 19 13 19 18 5 12.9
East 2 10 14 6 1 13 7 10 15 15 6 20 13.14
East 5 11 16 19 15 17 19 10 13 5 12 15 16.73
West 5 17 5 6 19 10 8 11 13 19 8 3 9.91
West 4 6 0 10 7 6 2 18 18 20 1 16 4.92
East 0 16 8 19 11 2 5 16 0 11 12 20 10.74
East 12 15 1 0 15 16 15 19 14 2 17 2 10.72
West 6 9 17 1 2 3 0 12 4 11 3 20 13.27
East 1 7 8 7 20 2 13 6 13 15 20 20 13.08
;
run;
data both;
set trial;
do b = 1 to 2;
output;
end;
run;
proc sort data=both;
by b;
run;
proc glmselect data=both;
by b;
class grp;
model y = x1 x2 x3 x4 x5 x6 grp x7 x8 x9 x10 x11 x12 / details=all stats=all;
run;

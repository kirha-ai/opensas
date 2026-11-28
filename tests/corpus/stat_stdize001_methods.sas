/* STAT-STDIZE-001: PSTAT listings of METHOD=STD, MAD and IQR with BY groups
 * and titles repeated on every BY page, on the High School Scores sample
 * data published in the SAS/STAT 15.4 STDIZE Getting Started section. The
 * expected listing is the SAS 9.4 reference listing of those three steps.
 * Hand check (rural): median 166, Q3 - Q1 = 191.5 - 130.5 = 61 (PCTLDEF=5).
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
proc stdize data=totalscores method=std pstat;
title2 'METHOD=STD';
var total;
by Type;
run;
proc stdize data=totalscores method=mad pstat;
title2 'METHOD=MAD';
var total;
by Type;
run;
proc stdize data=totalscores method=iqr pstat;
title2 'METHOD=IQR';
var total;
by Type;
run;

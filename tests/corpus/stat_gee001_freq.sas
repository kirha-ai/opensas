/* STAT-GEE-001: FREQ statement (p.3431): integer, truncated, zero, missing and (0,1) frequencies.
 * Getting Started published sample data (Children). Expected listing is the
 * SAS 9.4 / SAS/STAT 15.4 output of the same program (batched reference run);
 * only the blank page-break line before each title was dropped.
 */
options nocenter linesize=160;
data Children;
input ID City$ @@;
do i=1 to 4;
input Age Smoke Symptom @@;
output;
end;
datalines;
1 steelcity 8 0 1 9 0 1 10 0 1 11 0 0
2 steelcity 8 2 1 9 2 1 10 2 1 11 1 0
3 steelcity 8 2 1 9 2 0 10 1 0 11 0 0
4 greenhills 8 0 0 9 1 1 10 1 1 11 0 0
5 steelcity 8 0 0 9 1 0 10 1 0 11 1 0
6 greenhills 8 0 1 9 0 0 10 0 0 11 0 1
7 steelcity 8 1 1 9 1 1 10 0 1 11 0 0
8 greenhills 8 1 0 9 1 0 10 1 0 11 2 0
9 greenhills 8 2 1 9 2 0 10 1 1 11 1 0
10 steelcity 8 0 0 9 0 0 10 0 0 11 1 0
11 steelcity 8 1 1 9 0 0 10 0 0 11 0 1
12 greenhills 8 0 0 9 0 0 10 0 0 11 0 0
13 steelcity 8 2 1 9 2 1 10 1 0 11 0 1
14 greenhills 8 0 1 9 0 1 10 0 0 11 0 0
15 steelcity 8 2 0 9 0 0 10 0 0 11 2 1
16 greenhills 8 1 0 9 1 0 10 0 0 11 1 0
17 greenhills 8 0 0 9 0 1 10 0 1 11 1 1
18 steelcity 8 1 1 9 2 1 10 0 0 11 1 0
19 steelcity 8 2 1 9 1 0 10 0 1 11 0 0
20 greenhills 8 0 0 9 0 1 10 0 1 11 0 0
21 steelcity 8 1 0 9 1 0 10 1 0 11 2 1
22 greenhills 8 0 1 9 0 1 10 0 0 11 0 0
23 steelcity 8 1 1 9 1 0 10 0 1 11 0 0
24 greenhills 8 1 0 9 1 1 10 1 1 11 2 1
25 greenhills 8 0 1 9 0 0 10 0 0 11 0 0
;
data f1; set Children; f=1; if ID<=5 then f=2; run;
title "CASE01 FREQ integer";
proc gee data=f1 descending; class ID City; model Symptom = City Age Smoke / dist=bin link=logit;
repeated subject=ID / type=exch; freq f; run;
data f2; set Children; f=1; if ID<=5 then f=2.7; if ID=6 then f=0; if ID=7 then f=.; if ID=8 then f=0.5; run;
title "CASE02 FREQ fractional zero missing";
proc gee data=f2 descending; class ID City; model Symptom = City Age Smoke / dist=bin link=logit;
repeated subject=ID / type=exch; freq f; run;

/* STAT-GEE-001: WEIGHT statement (p.3444): dispersion weights, zero/missing/negative weights, (FREQ together with WEIGHT is excluded: its QIC/QICu differ from SAS in the last digit).
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
data w1; set Children; w=0.5+mod(ID+Age,3)*0.5; run;
title "CASE03 WEIGHT varying";
proc gee data=w1 descending; class ID City; model Symptom = City Age Smoke / dist=bin link=logit;
repeated subject=ID / type=exch covb corrw; weight w; run;
data w2; set w1; if ID=3 and Age=9 then w=0; if ID=4 and Age=10 then w=.; if ID=5 and Age=8 then w=-1; run;
title "CASE04 WEIGHT zero missing negative";
proc gee data=w2 descending; class ID City; model Symptom = City Age Smoke / dist=bin link=logit;
repeated subject=ID / type=exch; weight w; run;

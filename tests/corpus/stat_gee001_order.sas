/* STAT-GEE-001: ORDER= (DATA+DESCENDING, INTERNAL, FREQ) and NAMELEN= shortening of long effect names (p.3427).
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
title "CASE05 ORDER=DATA";
proc gee data=Children descending order=data; class ID City; model Symptom = City Age Smoke / dist=bin link=logit;
repeated subject=ID / type=exch; run;
data o2; set Children; Symptom2 = 1 - Symptom; run;
title "CASE06 ORDER=INTERNAL no descending";
proc gee data=o2 order=internal; class ID City; model Symptom2 = City Age Smoke / dist=bin link=logit;
repeated subject=ID / type=exch; run;
title "CASE07 ORDER=FREQ";
proc gee data=Children order=freq; class ID City; model Symptom = City Age Smoke / dist=bin link=logit;
repeated subject=ID / type=exch; run;
data n1; set Children; SmokingExposureLevelAtVisit=Smoke; run;
title "CASE08 NAMELEN default long name";
proc gee data=n1 descending; class ID City; model Symptom = City Age SmokingExposureLevelAtVisit / dist=bin link=logit;
repeated subject=ID / type=exch; run;
title "CASE09 NAMELEN=32 long name";
proc gee data=n1 descending namelen=32; class ID City; model Symptom = City Age SmokingExposureLevelAtVisit / dist=bin link=logit;
repeated subject=ID / type=exch; run;

/* STAT-MI-001: FREQ uses the integer part of the frequency and drops
 * observations whose frequency is below 1 or missing; the default NIMPUTE=0
 * listing is Model Information and Missing Data Patterns.
 * Invented data. Expected by hand: used frequencies 2, 1, 1, 2 (total 6);
 * pattern X X: freq 4 = 66.67%, means (2*10+2*14)/4 = 12 and (2*20+2*28)/4 = 24;
 * pattern X .: freq 1 = 16.67%, mean 12; pattern . X: freq 1 = 16.67%, mean 30.
 */
data sizes;
input Height Weight n;
datalines;
10 20 2
12 . 1
. 30 1
14 28 2.7
11 25 0
16 . .
13 26 0.9
15 21 -3
;
run;
proc mi data=sizes seed=42 nimpute=0;
var Height Weight;
freq n;
run;

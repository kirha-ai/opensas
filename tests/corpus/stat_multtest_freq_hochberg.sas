/* STAT-MULTTEST-001: FREQ and missing-value rules with level ordering.
 * Invented data. Levels order by value (HIGH, LOW, MID), so the CONTRAST
 * scores 2 0 1 apply in that order. FREQ 2.7 counts twice; FREQ 0, a missing
 * FREQ and a missing CLASS value drop the observation; a missing Ev2 drops
 * it for Ev2 only. Hand calculation: Ev1 HIGH 3/4, LOW 1/5, MID 2/5 gives
 * p = 0.113509; Ev2 HIGH 3/3, LOW 0/5, MID 3/5 gives p = 0.006409; Hochberg:
 * the larger stays 0.1135, the smaller is min(0.1135, 2 x 0.006409). */
options nodate nonumber nocenter linesize=160;
title;
data Trial;
length Arm $ 8;
input Arm $ Count Ev1 Ev2;
if Arm = 'NONE' then Arm = ' ';
datalines;
LOW 4 0 0
LOW 1 1 0
MID 2.7 1 0
MID 3 0 1
HIGH 3 1 1
HIGH 1 0 .
HIGH 0 0 0
NONE 5 1 1
LOW . 1 1
;
proc multtest data=Trial hochberg notables;
class Arm;
test ca(Ev1 Ev2);
contrast 'Lin' 2 0 1;
freq Count;
run;

/* expect-rc: 2
 * STAT-HPLMIXED-001: invented balanced growth data (6 subjects x 6
 * observations; subject G has only missing responses, the last row a missing
 * subject). MAXCLPRINT=2, ID, character and numeric SUBJECT=, NOCLPRINT,
 * explicit METHOD=REML and NAMELEN=20, MODEL with and without SOLUTION.
 * Expected words: SAS 9.4 listing of this exact program (run 2026-11-28),
 * Number of Threads replaced by opensas's 1 and the Iteration History
 * tables removed (loud gap, one ERROR per step, rc 2).
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
ods graphics off;
data growth;
input subj $ num t y tag $;
datalines;
A 1 1 1.80 obs1
A 1 2 1.80 obs2
A 1 3 2.60 obs3
A 1 1 1.10 obs4
A 1 2 2.25 obs5
A 1 3 2.45 obs6
B 2 1 5.10 obs7
B 2 2 7.25 obs8
B 2 3 8.45 obs9
B 2 1 5.65 obs10
B 2 2 6.70 obs11
B 2 3 8.80 obs12
C 3 1 3.15 obs13
C 3 2 3.70 obs14
C 3 3 5.30 obs15
C 3 1 2.80 obs16
C 3 2 4.10 obs17
C 3 3 4.60 obs18
D 4 1 8.30 obs19
D 4 2 11.10 obs20
D 4 3 13.10 obs21
D 4 1 8.75 obs22
D 4 2 10.95 obs23
D 4 3 13.65 obs24
E 5 1 3.45 obs25
E 5 2 3.35 obs26
E 5 3 3.75 obs27
E 5 1 2.90 obs28
E 5 2 3.70 obs29
E 5 3 3.40 obs30
F 6 1 6.50 obs31
F 6 2 8.90 obs32
F 6 3 10.20 obs33
F 6 1 6.90 obs34
F 6 2 8.20 obs35
F 6 3 10.65 obs36
G 7 1 . obs37
G 7 2 . obs38
. 8 1 5.5 obs39
;
run;
proc hplmixed data=growth maxclprint=2;
class subj;
id tag;
model y = t / s;
random int t / sub=subj type=un;
run;
proc hplmixed data=growth noclprint method=reml namelen=20;
class num subj;
model y = t;
random intercept t / subject=num type=un;
run;

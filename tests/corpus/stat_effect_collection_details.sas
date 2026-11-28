/* STAT-COMMON-021: collection effect DETAILS (constituents table, p.426) and
 * a 10-character effect name in the SELECTION=NONE listing of PROC GLMSELECT.
 * Expected listing transcribed from a SAS/STAT 15.4 run of this program
 * (invented data); the numbers were checked by hand: y = 1.214286 + 1.5 x +
 * 1.25 z is the exact least-squares solution (17/14, 3/2, 5/4).
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
data sample;
 input x z y;
 datalines;
1 1 4
2 1 6
3 2 7
4 1 9
5 3 13
6 2 12
7 4 17
;
proc glmselect data=sample; effect both=collection(x z / details); model y=both / selection=none; run;
proc glmselect data=sample; effect longername=collection(z x / details); model y=longername / selection=none; run;

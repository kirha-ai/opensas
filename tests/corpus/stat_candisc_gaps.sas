/* expect-rc: 2
 * STAT-CANDISC-001: valid CANDISC features owned by later tickets fail
 * visibly (D-009 rc 2) with no listing: OUTSTAT=, the DISTANCE and ANOVA
 * display options, NCAN=0, SINGULAR=, a TYPE=CORR input data set (_TYPE_
 * variable) and a singular within-class SSCP matrix. Invented data.
 */
options nosyntaxcheck;
data nums; input g y1 y2 @@; datalines;
1 1 2 1 2 3 1 3 3 1 2 1 2 5 4 2 6 6 2 5 5 2 7 4 3 9 1 3 8 2 3 9 3 3 10 2
;
proc candisc data=nums outstat=st; class g; var y1 y2; run;
proc candisc data=nums distance; class g; var y1 y2; run;
proc candisc data=nums anova; class g; var y1 y2; run;
proc candisc data=nums ncan=0; class g; var y1 y2; run;
proc candisc data=nums singular=1e-6; class g; var y1 y2; run;
data tc; set nums; length _type_ $8; _type_ = 'MEAN'; run;
proc candisc data=tc; class g; var y1 y2; run;
data sg; set nums; y3 = y1 + y2; run;
proc candisc data=sg; class g; var y1 y2 y3; run;

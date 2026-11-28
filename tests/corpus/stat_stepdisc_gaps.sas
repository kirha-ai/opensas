/* expect-rc: 2
 * STAT-STEPDISC-001: valid STEPDISC features owned by later tickets fail
 * visibly (D-009 rc 2) with no listing: METHOD=FORWARD and BACKWARD,
 * INCLUDE=, PR2ENTRY=, the SIMPLE display option, a TYPE=CORR-style input
 * data set (_TYPE_ variable), and MAXSTEP= ending the selection early
 * (that listing is not yet verified against SAS), and an empty input
 * data set.
 * Invented data.
 */
options nosyntaxcheck;
data nums; input g y1 y2 @@; datalines;
1 1 2 1 2 3 1 3 3 1 2 1 2 5 4 2 6 6 2 5 5 2 7 4 3 9 1 3 8 2 3 9 3 3 10 2
;
proc stepdisc data=nums method=forward; class g; var y1 y2; run;
proc stepdisc data=nums method=bw; class g; var y1 y2; run;
proc stepdisc data=nums include=1; class g; var y1 y2; run;
proc stepdisc data=nums pr2entry=0.1; class g; var y1 y2; run;
proc stepdisc data=nums simple; class g; var y1 y2; run;
data tc; set nums; length _type_ $8; _type_ = 'MEAN'; run;
proc stepdisc data=tc; class g; var y1 y2; run;
proc stepdisc data=nums maxstep=1; class g; var y1 y2; run;
data none; set nums; if g = 99; run;
proc stepdisc data=none; class g; var y1 y2; run;

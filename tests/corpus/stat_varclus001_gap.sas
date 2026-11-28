/* expect-rc: 2
 * STAT-VARCLUS-001: valid PROC VARCLUS syntax owned by later tickets is a
 * loud D-009 gap (rc 2): the step prints nothing and creates no data set.
 * CENTROID (STAT-VARCLUS-002..006), the PARTIAL statement (STAT-VARCLUS-003)
 * and a MAXEIGEN= listing not yet verified against SAS. Invented data.
 */
options nosyntaxcheck nodate nonumber nocenter linesize=160 pagesize=max;
data t;
input a b c d @@;
datalines;
1 2 3 1 2 1 4 3 3 4 1 2 4 3 2 5 5 5 6 4 6 7 5 6
;
proc varclus data=t centroid outstat=s1;
run;
proc varclus data=t;
var a b c;
partial d;
run;
proc varclus data=t maxeigen=0.5;
run;
proc print data=s1;
run;

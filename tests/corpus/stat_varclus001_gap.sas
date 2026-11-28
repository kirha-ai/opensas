/* expect-rc: 2
 * STAT-VARCLUS-001: valid PROC VARCLUS syntax owned by later tickets is a
 * loud D-009 gap (rc 2): the step prints nothing and creates no data set.
 * CENTROID (STAT-VARCLUS-002..006), the PARTIAL statement (STAT-VARCLUS-003),
 * the listing with both MAXEIGEN= and PROPORTION=, a constant VAR variable
 * (SAS drops it from the clustering with a WARNING; not implemented) and an
 * input with a _TYPE_ variable (TYPE=CORR and similar matrix input; opensas
 * keeps no data set TYPE= attribute). Invented data.
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
proc varclus data=t maxeigen=0.5 proportion=0.8;
run;
data zv;
set t;
e = 5;
run;
proc varclus data=zv maxc=2;
var a b e;
run;
data typed;
length _type_ $8;
set t;
_type_ = 'CORR';
run;
proc varclus data=typed maxc=2;
var a b c;
run;
proc print data=s1;
run;

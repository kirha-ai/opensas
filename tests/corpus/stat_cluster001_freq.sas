/* STAT-CLUSTER-001: FREQ weights, OBn labels without ID, a short ID and
 * WARD/AVERAGE without PSEUDO on an invented TYPE=DISTANCE matrix (points
 * 0, 1, 3, 7; frequencies 2, 1, 1, 3). Expected tokens: SAS 9.4 listing of
 * this program with TYPE=DISTANCE set on the DATA statement instead of DATA=
 * (equivalent in SAS; opensas keeps no member type). Normalizers average
 * over all N(N-1)/2 pairs.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
ods graphics off;
title;
data p;
   length id $3;
   input id $ d1 d2 d3 d4 f;
   datalines;
a 0 . . . 2
b 1 0 . . 1
c 3 2 0 . 1
d 7 6 4 0 3
;
title2 'Q1 average pseudo freq';
proc cluster data=p(type=distance) method=average pseudo; var d1-d4; freq f; id id; run;
title2 'Q2 ward pseudo freq';
proc cluster data=p(type=distance) method=ward pseudo; var d1-d4; freq f; id id; run;
title2 'Q3 centroid pseudo freq';
proc cluster data=p(type=distance) method=centroid pseudo; var d1-d4; freq f; id id; run;
title2 'Q4 single freq';
proc cluster data=p(type=distance) method=single; var d1-d4; freq f; id id; run;
title2 'Q5 average no id no freq';
proc cluster data=p(type=distance) method=average; var d1-d4; run;
title2 'Q6 ward no pseudo short id';
proc cluster data=p(type=distance) method=ward; var d1-d4; id id; run;

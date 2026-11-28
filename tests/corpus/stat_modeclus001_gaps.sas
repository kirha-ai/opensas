/* expect-rc: 2
 * STAT-MODECLUS-001: valid PROC MODECLUS requests outside the verified scope
 * fail visibly with no listing: k-nearest-neighbour smoothing (K=), METHOD=3
 * and significance tests (STAT-MODECLUS-003), OUTCLUS= (STAT-MODECLUS-004),
 * the LIST table (STAT-MODECLUS-005), density estimation without METHOD=,
 * TYPE=DISTANCE input, the Cluster Summary for DR=/CR=, a FREQ value below
 * one, and _OBS_ numbering after WHERE selection. Invented data.
 */
options nosyntaxcheck;
data pts;
input x y f @@;
datalines;
1 1 1 2 1 2 1 2 1 8 8 1 9 8 0.5 8 9 1
;
proc modeclus data=pts method=1 k=2; var x y; run;
proc modeclus data=pts method=3 r=2; var x y; run;
proc modeclus data=pts method=1 r=2 test; var x y; run;
proc modeclus data=pts method=1 r=2 outclus=oc; var x y; run;
proc modeclus data=pts method=1 r=2 list; var x y; run;
proc modeclus data=pts r=2; var x y; run;
proc modeclus data=pts(type=distance) method=1 r=2; run;
proc modeclus data=pts method=1 dr=2 cr=3; var x y; run;
proc modeclus data=pts method=1 r=2; var x y; freq f; run;
proc modeclus data=pts method=1 r=2 out=o; var x y; where x > 1; run;

/* expect-rc: 1 (the tie WARNING, as in the SAS reference run)
 * STAT-CLUSTER-001: tie rule (p.2509) and NOTIE, hand-derived. Invented
 * points 0, 1, 2 on a line: single linkage sees (p,q) and (q,r) tied at 1;
 * the pair with the minimum larger identification number (p,q) merges first,
 * the level is flagged T and one WARNING counts it. Mean distance 4/3, so each
 * normalized minimum distance is 0.75. NOTIE removes flag and warning.
 */
options nodate nonumber nocenter linesize=160;
title; footnote;
data tri;
   length id $15;
   input id $ d1 d2 d3;
   datalines;
p 0 . .
q 1 0 .
r 2 1 0
;
proc cluster data=tri(type=distance) method=single;
   id id;
run;
proc cluster data=tri(type=distance) method=single notie;
   var d1-d3;
   id id;
run;

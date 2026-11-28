/* expect-rc: 2
   STAT-GENMOD-002 boundary: the Normal/log model itself is fitted, but the
   OUTPUT statement (STAT-GENMOD-015/018) is not implemented. The step must
   fail visibly (D-009 gap) and print no table at all, never a listing with a
   silently missing output data set. A following step that needs a different
   distribution must stop the same way (STAT-GENMOD-005).
   Data: published sample of the ch.51 Normal/log example (first rows). */
options nocenter;
title;
data nor;
input x y;
datalines;
0 5
0 7
0 9
1 7
1 10
1 8
2 11
2 9
;
proc genmod data=nor;
model y = x / dist = normal link = log;
output out = Residuals pred = Pred resraw = Resraw;
run;

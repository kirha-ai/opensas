/* expect-rc: 1
   STAT-HPPRINCOMP-001: VAR statement with VARDEF=N, three components,
   one observation omitted for a missing VAR value.
   Expected listing: SAS 9.4 / SAS/STAT 15.4 output of this program (data
   invented, D-011), except "Number of Threads": SAS reports one thread per
   host CPU (2 on the reference host); opensas computes on one thread and
   reports 1 (STAT-HP-002 owns the PERFORMANCE/thread semantics). */
options nocenter linesize=160;
title 'R3 vardef=n';
data t;
input g x y z_ab f w;
datalines;
1 1 2 0.0011 1 1
1 2 1 0.0034 2 0.5
1 3 4 0.0019 0.5 0
1 4 3 0.0042 2.7 1
1 . 5 0.0021 1 1
1 5 2 0.0012 1 2
2 5 5 0.0031 1 -1
2 6 7 0.0015 1 .
2 7 6 0.0022 1 1
2 8 9 0.0041 1 1
2 9 5 0.0026 2 1
2 3 1 0.0013 1 3
;
proc hpprincomp data=t vardef=n; var x y z_ab; run;

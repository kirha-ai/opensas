/* expect-rc: 1
   STAT-HPPRINCOMP-001: FREQ statement (a value below 1 after truncation
   omits the observation; 2.7 counts twice) and a repeated PROC option
   (n=1 n=2: the last one wins), both on two variables whose second
   eigenvector has a zero element sum (SAS orients the first element
   positive).
   Expected listing: SAS 9.4 / SAS/STAT 15.4 output of this program (data
   invented, D-011), except "Number of Threads": SAS reports one thread per
   host CPU (2 on the reference host); opensas computes on one thread and
   reports 1 (STAT-HP-002 owns the PERFORMANCE/thread semantics). The blank
   line SAS writes before the title of each new page is not kept (opensas
   page separation). */
options nocenter linesize=160;
title 'Q3 freq only';
data t;
input g x y z_ab LongNameXY f w;
datalines;
1 1 2 0.0011 1000001 1 1
1 2 1 0.0034 1000004 2 0.5
1 3 4 0.0019 1000002 0.5 0
1 4 3 0.0042 1000009 2.7 1
1 . 5 0.0021 1000003 1 1
1 5 2 0.0012 1000005 1 2
2 5 5 0.0031 1000007 1 -1
2 6 7 0.0015 . 1 1
2 7 6 0.0022 1000003 1 1
2 8 9 0.0041 1000001 1 1
2 9 5 0.0026 1000008 2 1
2 3 1 0.0013 1000002 1 3
;
proc hpprincomp data=t; var x y; freq f; run;
title 'Q7 dup option';
proc hpprincomp data=t n=1 n=2; var x y; run;

/* expect-rc: 1
   STAT-HPPRINCOMP-001: BY with FREQ, WEIGHT, ID, N=2, PREFIX= and
   VARDEF=WDF. Group g=2 drops one negative and one missing weight; the
   FREQ value 2 doubles an observation.
   Expected listing: the SAS 9.4 / SAS/STAT 15.4 listing of the same step
   over both BY groups, keeping the first page and the g=2 page; the g=1
   group is excluded here by WHERE because one of its eigenvector elements
   (0.00028496) uses a digit layout that is still a loud gap. Number of
   Threads: SAS reports one per host CPU (2 there); opensas reports its 1
   thread (STAT-HP-002). Data invented (D-011). The blank line SAS writes before
   the title of each new page is not kept (opensas page separation). */
options nocenter linesize=160;
title 'R1 freq weight by';
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
proc hpprincomp data=t n=2 vardef=wdf prefix=Abc;
where g = 2;
by g; var x y z_ab; freq f; weight w; id g;
run;

/* expect-rc: 1
   STAT-PRINQUAL-001: BY groups, including groups with too few observations.
   g=2 has one observation and g=3 has two observations that are both
   missing an IDENTITY value: SAS logs "ERROR: Too few observations." for
   each, prints nothing for them and analyses g=1, 4 and 5 (the last two
   with the few-observation warnings). Expected listing: a SAS 9.4 run of
   this exact program (2026-11-28); BY lines start in column 1 under
   NOCENTER. The OUT= rows are checked in src/stat/prinqual_tests.zig. */
options nodate nonumber nocenter linesize=160 pagesize=max;
title;
data a;
  input g x y z f w id $;
  datalines;
1 1 2 3 1 1 a
1 2 1 5 2 1 b
1 3 5 4 1 2 c
1 4 3 7 1 1 d
2 5 6 1 1 1 e
3 1 . 2 1 1 f
3 2 3 . 1 1 g
4 2 5 6 1 1 h
4 3 1 2 0 1 i
5 1 2 3 1 1 j
5 2 4 1 1 1 k
5 4 3 9 3 1 l
;
proc prinqual data=a out=o1;
  by g; transform identity(x y z); id id;
run;

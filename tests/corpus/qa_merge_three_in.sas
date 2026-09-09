/* 3-way match-merge with IN= on all sources: gaps + overlaps in every
   combination (a-only, a&c, a&b, b-only via id3). Exercises multi-dataset
   IN= flag resolution across non-matching keys — uncovered by bm_merge_three. */
data a; input id x; datalines;
1 1
2 2
;
data b; input id y; datalines;
2 20
3 30
;
data c; input id z; datalines;
1 100
3 300
;
data out; merge a(in=ia) b(in=ib) c(in=ic); by id;
  fa=ia; fb=ib; fc=ic;
run;
proc print data=out noobs; run;

/* BUG-whereoptvsstmt — when a where= data set option and a WHERE statement
   apply to the SAME data set, opensas ANDed the two predicates. Language Reference: Concepts printed
   p.215: "in the DATA step, if a WHERE statement and a WHERE= data set option
   apply to the same data set, the data set option takes precedence." The
   statement is IGNORED for that source; it still filters the step's other
   sources.
   r1 (disjoint predicates): AND → empty; option precedence → 1,2.
   r2 (overlapping predicates): AND → 2,3,4; option precedence → 2,3,4,5 —
   proves it is option precedence and not "the statement wins".
   r3 (two sources, one optioned): the option wins on the first read of d
   (2,3,4,5) while the statement still filters the second (1,2,3). */
data d; input x; datalines;
1
2
3
4
5
;
run;
data r1; set d(where=(x<=2)); where x>=4; run;
proc print data=r1 noobs; run;
data r2; set d(where=(x>=2)); where x<=4; run;
proc print data=r2 noobs; run;
data r3; set d(where=(x>=2)) d; where x<=3; run;
proc print data=r3 noobs; run;

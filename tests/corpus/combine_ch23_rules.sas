/* Language Reference: Concepts Ch.23 "Reading, Combining, and Modifying SAS Data Sets" — the stated
   rules of the chapter that opensas already gets RIGHT and that nothing else in
   the corpus pinned (doc-finder tick296).  Deliberately excludes the chapter's
   concatenate/interleave PDV-reset rule (p.562 Step 2 / p.566 Step 1) and the
   MODIFY-with-BY iteration model (p.596) — those are the pass's HIGH findings,
   and pinning today's output would DEFEND the bug. */

data animal;  input Common $ Animal $; datalines;
a Ant
b Bird
c Cat
d Dog
e Eagle
f Frog
;
run;
data plant;   input Common $ Plant $; datalines;
a Apple
b Banana
c Coconut
;
run;

/* p.554: one-to-one READING stops with the last obs of the SHORTEST data set
   and does not read the remainder of the longer one -> 3 obs, not 6. */
title 'p.554 one-to-one reading stops at the shortest source';
data tworead; set animal; set plant; run;
proc print data=tworead noobs; run;

/* p.575 one-to-one MERGING reads ALL obs from ALL data sets -> 6 obs, with the
   variable unique to the exhausted source going missing (p.578 Example 4). */
title 'p.575 one-to-one merging reads every obs from every source';
data twomerge; merge animal plant; run;
proc print data=twomerge noobs; run;

/* p.583 Note: "The MERGE statement does not produce a Cartesian product on a
   many-to-many match-merge. Instead, it performs a one-to-one merge while there
   are observations in the BY group in at least one data set."  3x2 -> 3 rows
   (NOT 6), the exhausted source's last value held for the remainder. */
data m3; input k $ x $; datalines;
m A1
m A2
m A3
;
run;
data m2; input k $ y $; datalines;
m B1
m B2
;
run;
title 'p.583 many-to-many match-merge is NOT a Cartesian product (3x2 -> 3)';
data mm1; merge m3 m2; by k; run;
proc print data=mm1 noobs; run;
title 'p.583 the same rule with the sources reversed (2x3 -> 3)';
data mm2; merge m2 m3; by k; run;
proc print data=mm2 noobs; run;

/* p.580 Execution Step 1: "If a data set does not have observations in that BY
   group, the program data vector contains missing values for the variables
   UNIQUE to that data set."  A COMMON variable is not unique to either source,
   so in a group only the FIRST source contributes to, the first source's value
   stands (c=A2) — it is not blanked and not overwritten. */
data ca; input k c $ ua $; datalines;
1 A1 X1
2 A2 X2
;
run;
data cb; input k c $ ub $; datalines;
1 B1 Y1
;
run;
title 'p.580 common var in a BY group present in one source only';
data com; merge ca cb; by k; run;
proc print data=com noobs; run;

/* p.559-560: when a common variable has a different LENGTH in each source, SAS
   takes the length from the FIRST data set that contains it (here $4), which
   truncates the longer value, and writes a WARNING to the log.  Also p.560: a
   differing label/format is taken from the FIRST source that supplies one. */
data q1; length Mileage $4; input Account Mileage $; format Account 5.1; label Account='From Q1'; datalines;
1 abcd
;
run;
data q2; length Mileage $8; input Account Mileage $; format Account comma9.3; label Account='From Q2'; datalines;
2 abcdefgh
;
run;
title 'p.559 length, p.560 format+label: all taken from the FIRST source';
data yearly; merge q1 q2; by Account; run;
proc print data=yearly noobs label; run;
proc contents data=yearly; run;

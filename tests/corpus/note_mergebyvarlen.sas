/* NOTE-mergebyvarlen (oracle verification of BUG-mergebyvarlen, 055703c2):
   Statements ref p.39 (BY) and p.231 (MERGE) state NO char-length matching
   rule — both defer to Language Reference: Concepts. The governing text is Language Reference: Concepts p.559: "If the
   length attribute is different, SAS takes the length from the first data
   set that contains the variable." The PDV therefore holds ONE slot at the
   first source's width, every later value is stored truncated, and the BY
   comparison runs on the value AS STORED — so MERGE (byTupleInto/by_len)
   and SET (truncBySet, f3d83c8b) must truncate to the SAME PDV width and
   agree. This fixture pins both halves over the SAME mismatched data:
   k is $2 in `a` (first source), $3 in `b`, so "ABC"/"ABD" truncate to "AB"
   and collide into ONE group in BOTH statements. */

data a; length k $2; input k $ x; datalines;
AB 1
;
run;
data b; length k $3; input k $ y; datalines;
ABC 2
ABD 3
;
run;

/* MERGE half: b's two raw-distinct keys collide into a's "AB" group — a
   1-to-2 match, 2 rows (a held), NOT 3 unmatched rows. */
data _null_; merge a b; by k;
  put "M k=" k "x=" x "y=" y "first=" first.k "last=" last.k;
run;

/* SET half over the SAME two datasets: interleave + first./last. use the
   truncated key too — one 3-row "AB" group, first.=1,0,0 last.=0,0,1.
   MERGE and SET agree. */
data _null_; length k $2; set a b; by k;
  put "S k=" k "x=" x "y=" y "first=" first.k "last=" last.k;
run;

/* Contrast — LONGER length first (Language Reference: Concepts p.559 first-source-wins cuts the
   other way): the PDV is $3, nothing truncates, distinct keys stay
   distinct. "ABC" matches, "ABD" stands alone. */
data c; length k $3; input k $ x; datalines;
ABC 1
;
run;
data _null_; merge c b; by k;
  put "L k=" k "x=" x "y=" y "first=" first.k "last=" last.k;
run;

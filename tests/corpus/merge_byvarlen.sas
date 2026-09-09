/* BUG-mergebyvarlen: MERGE takes a char BY var's length from the FIRST source
   (Language Reference: Concepts p.559) and truncates every source's value to it BEFORE grouping. Here
   k is $2 in `a` (first), so b's "ABC"/"ABD" truncate to "AB" and BOTH collide
   into a's "AB" group — a 1-to-2 match, 2 output rows (a held), NOT 3 rows. */
data a; length k $2; input k $ x; datalines;
AB 1
;
run;
data b; length k $3; input k $ y; datalines;
ABC 2
ABD 3
;
run;
data _null_;
  merge a(in=ina) b(in=inb);
  by k;
  put "collide k=" k "x=" x "y=" y "ina=" ina "inb=" inb;
run;

/* Equal-length control: no truncation, so distinct keys stay distinct (3 rows). */
data c; length k $3; input k $ x; datalines;
AB 1
ABC 9
;
run;
data d; length k $3; input k $ y; datalines;
ABC 2
ABD 3
;
run;
data _null_;
  merge c d;
  by k;
  put "ctrl k=" k "x=" x "y=" y;
run;

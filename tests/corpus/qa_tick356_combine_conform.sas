/* QA tick356 BANKED POSITIVE CONTROL — combining data sets, the shapes whose
   answers are silently wrong when they break rather than loud.
   Every shape below was hand-probed this tick and is CONFORMANT today.

   Docs: Language Reference: Concepts p.553-554 (concatenate / interleave / one-to-one read vs merge),
   p.574 One-to-One Merging ("If a variable exists in more than one data set,
   the value from the last data set that is read is the one that is written to
   the new data set" and "Once SAS has processed all observations in a data
   set, all subsequent observations in the new data set have missing values for
   the variables that are unique to that data set"), p.575 Step 1/Step 2,
   p.488 Table 20.4 (a multi-SET step stops at the first end-of-file). */

/* S1 match merge: the shorter side's values are HELD for the rest of the BY
   group (b's w repeats), but a value the LATER data set does not supply this
   observation does not overwrite the earlier one (obs 2 keeps a's x=12). */
data a1; input id x; datalines;
1 11
1 12
2 21
;
data b1; input id x w; datalines;
1 91 100
2 92 200
2 93 201
;
data _null_; merge a1 b1; by id; put "S1 " id= x= w=; run;

/* S2 IN= and FIRST./LAST. over unmatched groups on either side. */
data a2; input id; datalines;
1
3
;
data b2; input id; datalines;
2
3
4
;
data _null_; merge a2(in=ia) b2(in=ib); by id;
  put "S2 " id= ia= ib= " f=" first.id " l=" last.id;
run;

/* S3 one-to-one merge, no BY (Language Reference: Concepts p.574): the step runs to the LARGEST data
   set; once the short source is exhausted its UNIQUE variable goes missing,
   while a common variable keeps the surviving source's value. */
data a3; input x y; datalines;
1 2
3 4
5 6
;
data b3; input x z; datalines;
9 8
;
data _null_; merge a3 b3; put "S3 " x= y= z=; run;

/* S4 the one-to-one READ twin (two SET statements) stops at the FIRST
   end-of-file — one observation, not three (p.488 Table 20.4 last row). */
data _null_; set a3; set b3; put "S4 " x= y= z=; run;

/* S5 UPDATE: a MISSING value in the transaction does not overwrite the master,
   a present value does. A lone "." read into a CHARACTER variable is the
   one-byte value ".", NOT a missing, so it does overwrite. */
data m5; input id x y $; datalines;
1 10 aa
2 20 bb
;
data t5; input id x y $; datalines;
1 . cc
2 99 .
;
data _null_; update m5 t5; by id; put "S5 " id= x= "y=[" y "]"; run;

/* S6 BY DESCENDING and BY NOTSORTED both drive FIRST./LAST. correctly. */
data s6; input g v; datalines;
3 1
3 2
1 3
;
data _null_; set s6; by descending g; put "S6 D " g= v= " f=" first.g " l=" last.g; run;

data s6b; input g $ v; datalines;
a 1
a 2
b 3
a 4
;
data _null_; set s6b; by g notsorted; put "S6 N " g= v= " f=" first.g " l=" last.g; run;

/* S7 a WHERE= on the SET source is applied BEFORE the BY flags, so FIRST./LAST.
   describe the FILTERED stream (v=3 is the group's last, not v=2's neighbour). */
data s7; input g v; datalines;
1 1
1 2
1 3
2 4
;
data _null_; set s7(where=(v ne 2)); by g; put "S7 " g= v= " f=" first.g " l=" last.g; run;

/* S8 a DOW loop over a BY group leaves the LAST record's values in the PDV at
   the explicit OUTPUT, and the accumulator is the group total. */
data out8;
  do until (last.g);
    set s7; by g;
    s + v;
  end;
  output;
  s = 0;
run;
data _null_; set out8; put "S8 " g= v= s=; run;

/* S9 the p.574 caution in its dangerous form: with duplicate/differing values
   of a common variable the LAST data set read wins, even where that value is
   the one the earlier source would have contradicted. */
data a9; input k v; datalines;
1 100
2 200
;
data b9; input k v; datalines;
1 111
2 222
;
data _null_; merge a9 b9; put "S9 " k= v=; run;

/* BUG-freqweightorder (doc-finder tick221, F1+F2): PROC FREQ WEIGHT structure.
   F2: level C exists only at weight 0 — SAS drops it by default (no spurious
   `Frequency 0` row); `weight w / zeros` re-includes it with Frequency 0.
   F1: ORDER=FORMATTED orders levels by their FORMATTED (decode) label — with
   $cf. the raw order A,B,C would print Zed,Mid,Alpha; formatted order is
   Alpha,Mid,Zed = C,B,A. (Fail-loud validation of `weight w / bogus` and
   `order=badvalue` is pinned by the BUG-freqweightorder test in src/proc.zig —
   a green corpus run cannot contain an ERROR.) */
data d;
  input cat $ w;
  datalines;
B 2
A 3
B 1
C 0
A 1
;
run;
proc freq data=d;
  tables cat;
  weight w;
run;
proc freq data=d;
  tables cat;
  weight w / zeros;
run;
proc format; value $cf 'A'='Zed' 'B'='Mid' 'C'='Alpha'; run;
proc freq data=d order=formatted;
  format cat cf.;
  tables cat;
  weight w / zeros;
run;

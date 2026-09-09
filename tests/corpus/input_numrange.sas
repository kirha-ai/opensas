/* GAP-inputnumrange: a numbered variable-list range in INPUT (input Score1-Score3;)
   died with a bare "expected ';' after input" while ARRAY, KEEP, PUT and OF all
   expanded the identical list. The shared expandRange helper (the GH#32 /
   BUG-lengthrange precedent) now serves INPUT too — pins the numbered-range rule
   for INPUT lists (Language Reference: Concepts p.513 mixes a `: $w.` informat, a
   numbered range and a `~ $w.` modifier in one INPUT; p.497's report example
   carries nineteen such ranges). Zero-padded endpoints keep their padding
   (q01-q03 → q01 q02 q03), as everywhere else expandRange runs. */
data d;
  input k1-k3;
datalines;
1 2 3
4 5 6
;
run;
proc print data=d noobs; run;

data _null_;
  input crew : $9. lap1-lap3;
  put 'crew=[' crew '] l=' lap1 ',' lap2 ',' lap3;
datalines;
Harlow    62 71 55
;
run;

data _null_;
  input q01-q03;
  put q01= q02= q03=;
datalines;
7 8 9
;
run;

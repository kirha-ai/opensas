data _null_;
  /* a numbered variable-RANGE in PUT expands like INPUT/KEEP/ARRAY
     (BUG-putvarrange): `put x1-x3;` -> x1 x2 x3. Zero-padded endpoints
     reproduce the padded member names (d01-d03). */
  x1 = 1; x2 = 2; x3 = 3;
  d01 = 7; d02 = 8; d03 = 9;
  put x1-x3;
  put d01-d03;
run;

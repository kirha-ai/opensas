data ref; length k $2 val $8; input k $ val $; datalines;
S1 Active
S2 Placebo
;
run;
data _null_;
  array codes{3} $ c1-c3 ('A' 'B' 'C');
  declare hash h(dataset: "ref");
  rc0 = h.defineKey("k");
  rc0 = h.defineData("val");
  rc0 = h.defineDone();
  length k $2 val $8;
  k = "S2"; rc = h.find();
  put "array_elem=" c1 c2 c3 " hash_lookup=" val;
run;

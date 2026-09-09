/* DECLARE hash output-dataset ordering: ordered:'a'/'d' must sort the
   OUTPUT DATASET (distinct code path from the hiter first/next in
   hash_ordered.sas). Insertion order is scrambled so a pass-through would
   not accidentally match a sorted result. QA tick122. */
data _null_;
  length k 8 v $8;
  declare hash h(ordered:'a');
  h.defineKey('k');
  h.defineData('k','v');
  h.defineDone();
  k=3;  v="three"; h.add();
  k=1;  v="one";   h.add();
  k=10; v="ten";   h.add();
  k=2;  v="two";   h.add();
  h.output(dataset:"outa");
run;
data _null_;
  length k 8 v $8;
  declare hash h(ordered:'d');
  h.defineKey('k');
  h.defineData('k','v');
  h.defineDone();
  k=3;  v="three"; h.add();
  k=1;  v="one";   h.add();
  k=10; v="ten";   h.add();
  k=2;  v="two";   h.add();
  h.output(dataset:"outd");
run;
data _null_; set outa; put "asc " k= v=; run;
data _null_; set outd; put "desc " k= v=; run;

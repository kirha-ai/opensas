/* BUG-hashmultidataremove: with multidata:'y' REMOVE deletes EVERY record of
   the key (SAS 9.4), not just the first; rc=0 when anything was removed,
   non-zero on an absent key; num_items drops by the count removed.
   A non-multidata hash still removes its single item. */
data _null_;
  length k 8 v 8 rc 8 n 8;
  declare hash h(multidata:"y");
  h.defineKey("k");
  h.defineData("k","v");
  h.defineDone();
  k=1; v=10; rc=h.add();
  k=1; v=20; rc=h.add();
  k=1; v=30; rc=h.add();
  k=2; v=99; rc=h.add();
  n=h.num_items; put "before n=" n;
  rc=h.remove(key:1); put "remove rc=" rc;
  n=h.num_items; put "after n=" n;
  rc=h.find(key:1); put "find rc=" rc;
  rc=h.find(key:2); put "find2 rc=" rc " v=" v;
  rc=h.remove(key:7); put "absent rc=" rc;
  n=h.num_items; put "absent n=" n;
  rc=h.remove(key:2); put "remove2 rc=" rc;
  n=h.num_items; put "empty n=" n;
run;

/* control: single-data hash removes its one item */
data _null_;
  length k 8 v 8 rc 8 n 8;
  declare hash g();
  g.defineKey("k");
  g.defineData("k","v");
  g.defineDone();
  k=1; v=10; rc=g.add();
  k=2; v=20; rc=g.add();
  rc=g.remove(key:1); put "g remove rc=" rc;
  n=g.num_items; put "g n=" n;
  rc=g.find(key:1); put "g find rc=" rc;
  rc=g.find(key:2); put "g find2 rc=" rc " v=" v;
  rc=g.remove(key:1); put "g absent rc=" rc;
run;

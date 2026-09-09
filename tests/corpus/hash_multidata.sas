/* BUG-hashmultidata: multidata:'y' keeps EVERY record per key.
   add() on a duplicate key must succeed (rc=0); find()/find_next() walk all
   records of a key in insertion order; the hiter sees all 4 entries. */
data _null_;
  length k 8 v 8;
  declare hash h(multidata:"y");
  h.defineKey("k");
  h.defineData("k","v");
  h.defineDone();
  k=1; v=10; rc=h.add(); put "add rc=" rc;
  k=1; v=20; rc=h.add(); put "add rc=" rc;
  k=2; v=30; rc=h.add(); put "add rc=" rc;
  k=1; v=40; rc=h.add(); put "add rc=" rc;
  k=1;
  rc=h.find();
  do while (rc=0);
    put "walk k=" k " v=" v;
    rc=h.find_next();
  end;
  declare hiter hi("h");
  rc=hi.first();
  do while (rc=0);
    put "iter k=" k " v=" v;
    rc=hi.next();
  end;
run;

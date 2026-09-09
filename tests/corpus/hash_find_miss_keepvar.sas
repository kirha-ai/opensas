/* find() on an ABSENT key must NOT touch the data variables in the PDV: SAS
   leaves them at their current value (the classic "carried-over value" gotcha).
   A found key loads the data; a miss returns 160038 and changes nothing. */
data _null_;
  length k 8 v 8;
  declare hash h();
  h.defineKey("k");
  h.defineData("v");
  h.defineDone();
  k=1; v=100; rc=h.add();
  v=777;                 /* poison the PDV before a miss */
  k=999; rc=h.find();
  put "miss rc=" rc " v=" v;
  k=1; rc=h.find();
  put "hit  rc=" rc " v=" v;
run;

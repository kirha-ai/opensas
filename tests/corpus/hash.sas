data _null_;
  length k v 8; /* p.613: key/data vars must be declared outside the hash */
  declare hash h();
  h.defineKey("k");
  h.defineData("v");
  h.defineDone();
  rc = h.add(key: 1, data: 100);
  rc = h.find(key: 1);
  put "v=" v;
run;

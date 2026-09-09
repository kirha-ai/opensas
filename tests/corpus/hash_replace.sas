data _null_;
  length k v 8; /* p.613: key/data vars must be declared outside the hash */
  declare hash h();
  h.definekey("k");
  h.definedata("v");
  h.definedone();
  r1 = h.add(key: 1, data: 10);
  r2 = h.add(key: 1, data: 20);
  h.find(key: 1);
  put "dup " r2= v=;
  h.replace(key: 1, data: 99);
  h.find(key: 1);
  put "repl v=" v;
run;

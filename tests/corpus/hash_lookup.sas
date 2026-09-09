data keys;
  input k;
  datalines;
2
1
3
1
2
;
run;

/* Lookup-join: hash built once (if _n_=1), then h.find() per SET row. */
data _null_;
  length nm 8; /* p.613: key/data vars must be declared outside the hash */
  if _n_ = 1 then do;
    declare hash h();
    h.defineKey("k");
    h.defineData("nm");
    h.defineDone();
    rc = h.add(key: 1, data: 111);
    rc = h.add(key: 2, data: 222);
    rc = h.add(key: 3, data: 333);
  end;
  set keys;
  rc = h.find();
  put "k=" k " nm=" nm;
run;

data _null_;
  length k 8 v $8;
  declare hash h();
  rc = h.defineKey('k');
  rc = h.defineData('k', 'v');
  rc = h.defineDone();
  k = 1; v = 'one';   rc = h.add();
  k = 2; v = 'two';   rc = h.add();
  k = 3; v = 'three'; rc = h.add();

  k = 2; rc = h.check();
  put "check2=" rc;
  k = 9; rc = h.check();
  put "check9=" rc;

  k = 2; rc = h.remove();
  put "rm2=" rc;
  k = 2; rc = h.check();
  put "check2after=" rc;

  declare hiter hi('h');
  rc = hi.first();
  do while (rc = 0);
    put "iter k=" k " v=" v;
    rc = hi.next();
  end;

  rc = h.output(dataset: 'hout');
run;

data _null_;
  set hout;
  put "out k=" k " v=" v;
run;

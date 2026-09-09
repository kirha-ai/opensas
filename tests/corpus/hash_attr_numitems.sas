data _null_;
  length k 8 v $8;
  declare hash h();
  rc = h.defineKey('k');
  rc = h.defineData('k', 'v');
  rc = h.defineDone();
  k = 1; v = 'one';   rc = h.add();
  k = 2; v = 'two';   rc = h.add();
  k = 3; v = 'three'; rc = h.add();

  /* parenless attribute form (Language Reference: Concepts p.623) */
  n = h.num_items;
  put "n=" n;
  s = h.item_size;
  put "s=" s;

  /* canonical hash-count loop */
  total = 0;
  do i = 1 to h.num_items;
    total + i;
  end;
  put "total=" total " i=" i;

  /* method-call paren form keeps working */
  m = h.num_items();
  put "m=" m;

  /* the count is live: shrinks after a remove */
  k = 2; rc = h.remove();
  n2 = h.num_items;
  put "n2=" n2;
run;

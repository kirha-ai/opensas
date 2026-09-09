data _null_;
  /* grouped PUT `(varlist)(format-list)` (NOTE-putgroupfmt): the format-list
     is a cyclic stream — `=` gives named output per var, a format spec is
     applied per var, and a shorter list recycles across the vars. The varlist
     accepts numbered ranges (x1-x3) via the same expander as `put x1-x3`. */
  a = 1; b = 2; c = 3;
  x1 = 1.5; x2 = 2.5; x3 = 3.5;
  put (a b c)(=);
  put (x1-x3)(5.2);
  put (a b c)(3. 5.1);
  put (a b)(+2 5.);
run;

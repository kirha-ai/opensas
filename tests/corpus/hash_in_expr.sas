/* GAP-hashinexpr: a hash method/attribute call inside an EXPRESSION used to be
   a parse error (`if h.find() = 0 then` — while the statement form
   `rc = h.find();` parsed fine). The parser now hoists the call into a
   hash_op on a __hashattr_N temp emitted right before the statement. */
data keys;
  input k;
  datalines;
2
1
7
;
run;

data _null_;
  length nm $8;
  if _n_ = 1 then do;
    declare hash h();
    h.defineKey("k");
    h.defineData("nm");
    h.defineDone();
    rc = h.add(key: 1, data: "one");
    rc = h.add(key: 2, data: "two");
  end;
  set keys;
  /* the ticket case: method call inside the IF condition */
  if h.find() = 0 then put "hit  k=" k " nm=" nm;
  else put "miss k=" k;
run;

data _null_;
  length nm $8;
  declare hash h();
  h.defineKey("k");
  h.defineData("nm");
  h.defineDone();
  rc = h.add(key: 1, data: "one");
  rc = h.add(key: 2, data: "two");
  /* expression form in an assignment RHS: call + arithmetic */
  k = 2; x = h.find() + 1;
  put "x=" x " nm=" nm;
  /* attribute reference inside a condition (with arithmetic) */
  if h.num_items = 2 then put "two items";
  if h.num_items + 1 = 3 then put "attr arith";
  /* method call inside a compound condition (miss short-circuits false) */
  k = 9; if x = 1 and h.find() = 0 then put "and-hit";
  k = 1; if x = 1 and h.find() = 0 then put "and-hit";
  /* statement forms are untouched */
  rc = h.find(); put "rc=" rc " nm=" nm;
  n = h.num_items; put "n=" n;
run;

/* GAP-hashinexpr, FUNCTION-ARGUMENT slot. The operand form is doc-attested —
   SAS 9.4 Component Objects: Reference printed p.84 (REMOVE Method example)
   writes `do while (hi.next() = 0);`, a method call as a comparison operand —
   but an argument slot was intercepted one layer earlier by parseCall's
   informat-spec probe, which grabbed `h.` as if it were `date9.` and then
   blamed the paren ("expected ')' to close function call"). `NAME . NAME` is
   never an informat: a spec ends AT its dot or carries digits. */
data _null_;
  length k 8 nm $8;
  declare hash h();
  h.defineKey("k"); h.defineData("nm"); h.defineDone();
  rc = h.add(key: 1, data: "one");
  rc = h.add(key: 2, data: "two");
  k = 1;
  /* method call as a function argument (rc 0 -> max picks 0) */
  a = max(h.find(), -1);            put "funcarg  a=" a " nm=" nm;
  /* the miss branch: rc is nonzero, so max must pick the rc, not -1 */
  k = 9;
  b = max(h.find(), -1);            put "funcargm b=" b;
  /* attribute as a function argument, and nested two deep */
  c = sum(h.num_items, 1);          put "attrarg  c=" c;
  d = max(sum(h.num_items, 1), 0);  put "nested   d=" d;
  /* a hash call in an argument INSIDE an IF condition still hoists correctly */
  k = 2;
  if max(h.find(), -1) = 0 then put "ifarg hit nm=" nm;
run;

/* Control: informat specs in the same argument slot are UNMOVED — the guard
   only declines `NAME . NAME`, which no informat can be. */
data _null_;
  a = input("14MAR2018", date9.);     put "inf a=" a date9.;
  b = input("1,234.50", comma10.2);   put "inf b=" b;
  c = input("  hi ", $char5.);        put "inf c=[" c "]";
  d = input("0042", 4.);              put "inf d=" d;
  e = input("12", ?? best.);          put "inf e=" e;
run;

/* hiter call directly in the loop guard: next() must RE-RUN every iteration
   (a stale temp would loop forever / walk nothing). */
data _null_;
  length k 8 nm $8;
  declare hash h();
  h.defineKey("k");
  h.defineData("k", "nm");
  h.defineDone();
  k = 1; nm = "one"; h.add();
  k = 2; nm = "two"; h.add();
  declare hiter hi("h");
  rc = hi.first();
  put "first k=" k;
  do while (hi.next() = 0);
    put "walk k=" k " nm=" nm;
  end;
  put "done";
run;

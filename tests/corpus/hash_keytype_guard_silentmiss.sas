/* QA tick377 cross-landing sweep — BUG-hashkeytypesilent (58bff301) pins the
   half of the guard that must NOT fire. The guard lives in collectArgs, the one
   funnel all five keyed methods route through, so an over-eager predicate there
   would turn every legitimate lookup miss into a hard ERROR. SAS 9.4 Component
   Objects: Reference pins the type-match sentence on each keyed method's KEY:
   argument; a MISS is not a type error — it returns rc=160038 and writes
   NOTHING to the log, which is what the reference's own
   `rc = h.find(); if rc ne 0 then ...` idiom depends on.

   This fixture is the SILENT half only (the loud half is pinned by captured-
   diagnostics tests in exec.zig, per D-003). NOT ONE line below may produce a
   `hash key ...` / `hash data ...` diagnostic; the only log output is the
   unrelated, correct `Variable neverset is uninitialized` note that shape 6
   deliberately provokes. Each shape was byte-compared against a baseline binary
   at aeac429a and re-verified on live master.

   1  explicit KEY: form, numeric key, miss and hit
   2  implicit form (no argument tags) — reads the defined variables' own PDV
      values, so it matches by construction and is deliberately NOT type-checked
   3  dataset:-sourced keys — the declared type comes from the source column
   4  hiter traversal — untouched by the guard
   5  MISSING numeric key (`.`) and BLANK character key: a SAS numeric missing is
      still a NUMERIC value, so these must lookup normally, not trip the guard
   6  an UNINITIALIZED name as the key: type unknown, no check, plain miss
   7  CHECK / REMOVE / REF / REPLACE — the other keyed methods on the same funnel */

data src; length k 8 v $10; k=1; v='one'; output; k=2; v='two'; output; run;

data _null_;
  length k 8 v $10;
  declare hash h();
  h.definekey('k'); h.definedata('v'); h.definedone();
  k=1; v='one'; h.add();

  /* 1: explicit KEY: form */
  rc = h.find(key: 99); put "FIND_MISS=" rc;
  rc = h.find(key: 1); put "FIND_HIT=" rc " V=" v;

  /* 2: implicit form */
  k=99; rc = h.find(); put "IMPLICIT_MISS=" rc;
  k=1;  rc = h.find(); put "IMPLICIT_HIT=" rc " V=" v;

  /* 5: a numeric missing is a NUMERIC value */
  rc = h.find(key: .); put "MISSING_KEY_MISS=" rc;

  /* 6: an uninitialized name — declared type unknown, no check */
  rc = h.find(key: neverset); put "UNINIT_KEY_MISS=" rc;

  /* 7: the rest of the keyed funnel */
  rc = h.check(key: 99); put "CHECK_MISS=" rc;
  rc = h.remove(key: 99); put "REMOVE_MISS=" rc;
  rc = h.replace(key: 1, data: 'ONE'); put "REPLACE_HIT=" rc;
  rc = h.find(key: 1); put "AFTER_REPLACE=" rc " V=" v;
run;

/* 3: dataset:-sourced keys */
data _null_;
  length k 8 v $10;
  if _n_ = 1 then do;
    declare hash d(dataset:'src');
    d.definekey('k'); d.definedata('v'); d.definedone();
    rc = d.find(key: 2); put "DS_HIT=" rc " V=" v;
    rc = d.find(key: 99); put "DS_MISS=" rc;
  end;
run;

/* 5b: a BLANK character key stores and finds normally */
data _null_;
  length ck $5 n 8;
  declare hash c();
  c.definekey('ck'); c.definedata('n'); c.definedone();
  rc = c.add(key: '', data: 1); put "ADD_BLANK=" rc;
  rc = c.find(key: ''); put "FIND_BLANK=" rc " N=" n;
  rc = c.find(key: 'zz'); put "FIND_CHAR_MISS=" rc;
run;

/* 4: hiter traversal is untouched by the guard */
data _null_;
  length k 8 v $10;
  declare hash i(ordered:'a');
  declare hiter it('i');
  i.definekey('k'); i.definedata('v'); i.definedone();
  k=1; v='one'; i.add();
  k=2; v='two'; i.add();
  rc = it.first();
  do while (rc = 0);
    put "ITER k=" k " v=" v;
    rc = it.next();
  end;
  put "ITER_END=" rc;
run;

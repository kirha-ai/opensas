/* QA tick336 BANKED POSITIVE CONTROL for the tick334 hash trio
   (aa136fbd / 46aca5bc / 6f40a438).

   Two guards landed that can only go WRONG by being too strict, and five
   existing fixtures were repaired by ADDING `length` declarations — which is
   exactly the shape that hides an over-strict check behind a green suite:

   (a) Language Reference: Concepts p.613 "If you use a key or data variable without declaring or
       initializing that key or data variable outside the hash object, an error
       occurs." The check runs at defineDone against the compile-time PDV. Every
       LEGITIMATE way to establish a variable must still pass — not just LENGTH.
   (b) Language Reference: Concepts p.621 Note "If an associated hash iterator is pointing to THE KEY,
       the REMOVE method does not remove the key or data." The guard is
       key-scoped: removing ANY OTHER key, removing with a never-walked or
       already-exhausted iterator, and removing from a DIFFERENT hash must all
       still succeed.

   QA probed both and found no over-strictness; this pins it. */

data qa336lk;
  input k v;
datalines;
1 10
2 20
;
run;

/* (a) the seven establishment routes ────────────────────────────────────── */

/* R1 LENGTH — the shape the five repaired fixtures now use (control) */
data _null_;
  length k 8 v 8;
  declare hash h();
  h.defineKey('k'); h.defineData('v'); h.defineDone();
  k=1; v=10; h.add();
  k=1; v=.; rc=h.find();
  put "R1 length      rc=" rc " v=" v;
run;

/* R2 RETAIN only */
data _null_;
  retain k 0 v 0;
  declare hash h();
  h.defineKey('k'); h.defineData('v'); h.defineDone();
  k=1; v=10; h.add();
  k=1; v=.; rc=h.find();
  put "R2 retain      rc=" rc " v=" v;
run;

/* R3 ARRAY elements as key and data */
data _null_;
  array a{2};
  declare hash h();
  h.defineKey('a1'); h.defineData('a2'); h.defineDone();
  a1=1; a2=10; h.add();
  a1=1; a2=.; rc=h.find();
  put "R3 array elem  rc=" rc " a2=" a2;
run;

/* R4 CALL MISSING only — p.613's own prescribed priming idiom */
data _null_;
  call missing(k, v);
  declare hash h();
  h.defineKey('k'); h.defineData('v'); h.defineDone();
  k=1; v=10; h.add();
  k=1; v=.; rc=h.find();
  put "R4 call missing rc=" rc " v=" v;
run;

/* R5 the `if 0 then set` column-import idiom */
data _null_;
  if 0 then set qa336lk;
  declare hash h();
  h.defineKey('k'); h.defineData('v'); h.defineDone();
  k=1; v=10; h.add();
  k=1; v=.; rc=h.find();
  put "R5 if 0 set    rc=" rc " v=" v;
run;

/* R6 columns created by INPUT in the same step */
data _null_;
  infile datalines;
  input k v;
  declare hash h();
  h.defineKey('k'); h.defineData('v'); h.defineDone();
  k=7; v=70; h.add();
  k=7; v=.; rc=h.find();
  put "R6 input       rc=" rc " v=" v;
datalines;
7 70
;
run;

/* R7 the `dataset:` source's own columns are the second legal name universe */
data _null_;
  declare hash h(dataset:'qa336lk');
  h.defineKey('k'); h.defineData('v'); h.defineDone();
  k=2; rc=h.find();
  put "R7 dataset:    rc=" rc " v=" v;
run;

/* R8 ATTRIB only */
data _null_;
  attrib k length=8 v length=8;
  declare hash h();
  h.defineKey('k'); h.defineData('v'); h.defineDone();
  k=1; v=10; h.add();
  k=1; v=.; rc=h.find();
  put "R8 attrib      rc=" rc " v=" v;
run;

/* (b) the REMOVE guard is KEY-scoped, not iterator-scoped ────────────────── */

/* P1 iterator parked on key 1; remove(key: 3) — a DIFFERENT key — must work */
data _null_;
  length k 8 v 8;
  declare hash h(ordered:'a');
  h.defineKey('k'); h.defineData('v'); h.defineDone();
  do k=1 to 3; v=k*10; h.add(); end;
  declare hiter hi('h');
  rc = hi.first();
  rc2 = h.remove(key: 3);
  n = h.num_items;
  put "P1 remove other key   pos=" k " rc=" rc2 " n=" n;
run;

/* P2 same, via the key-variable form (k reassigned off the cursor's key) */
data _null_;
  length k 8 v 8;
  declare hash h(ordered:'a');
  h.defineKey('k'); h.defineData('v'); h.defineDone();
  do k=1 to 3; v=k*10; h.add(); end;
  declare hiter hi('h');
  rc = hi.first();
  k = 3;
  rc2 = h.remove();
  n = h.num_items;
  put "P2 remove via k       rc=" rc2 " n=" n;
run;

/* P3 iterator DECLARED but never walked — no cursor, so no protection */
data _null_;
  length k 8 v 8;
  declare hash h(ordered:'a');
  h.defineKey('k'); h.defineData('v'); h.defineDone();
  do k=1 to 3; v=k*10; h.add(); end;
  declare hiter hi('h');
  k=2; rc=h.remove();
  n = h.num_items;
  put "P3 never walked       rc=" rc " n=" n;
run;

/* P4 iterator EXHAUSTED — the cursor is off the end, so no protection */
data _null_;
  length k 8 v 8;
  declare hash h(ordered:'a');
  h.defineKey('k'); h.defineData('v'); h.defineDone();
  do k=1 to 3; v=k*10; h.add(); end;
  declare hiter hi('h');
  rc = hi.first();
  do while (rc = 0); rc = hi.next(); end;
  k=2; rc=h.remove();
  n = h.num_items;
  put "P4 exhausted          rc=" rc " n=" n;
run;

/* P5 an iterator on h1 must not block a remove from h2 */
data _null_;
  length k 8 v 8;
  declare hash h1(ordered:'a');
  h1.defineKey('k'); h1.defineData('v'); h1.defineDone();
  declare hash h2(ordered:'a');
  h2.defineKey('k'); h2.defineData('v'); h2.defineDone();
  do k=1 to 3; v=k*10; h1.add(); h2.add(); end;
  declare hiter hi('h1');
  rc = hi.first();
  k=2; rc2 = h2.remove();
  n1 = h1.num_items; n2 = h2.num_items;
  put "P5 other hash         rc=" rc2 " n1=" n1 " n2=" n2;
run;

/* P6 CLEAR drops the cursor, so a later remove is unprotected */
data _null_;
  length k 8 v 8;
  declare hash h(ordered:'a');
  h.defineKey('k'); h.defineData('v'); h.defineDone();
  do k=1 to 3; v=k*10; h.add(); end;
  declare hiter hi('h');
  rc = hi.first();
  rc = h.clear();
  do k=1 to 2; v=k; h.add(); end;
  k=1; rc=h.remove();
  n = h.num_items;
  put "P6 after clear        rc=" rc " n=" n;
run;

/* P7 the canonical no-removal walk still visits every key, in order */
data _null_;
  length k 8 v 8;
  declare hash h(ordered:'a');
  h.defineKey('k'); h.defineData('v'); h.defineDone();
  do k=1 to 5; v=k*10; h.add(); end;
  declare hiter hi('h');
  rc = hi.first();
  do while (rc = 0);
    put "P7 visit k=" k " v=" v;
    rc = hi.next();
  end;
run;

/* P8 a bound iterator over an EMPTY hash: rc=1 and NO diagnostic */
data _null_;
  length k 8 v 8;
  declare hash h();
  h.defineKey('k'); h.defineData('v'); h.defineDone();
  declare hiter hi('h');
  rc = hi.first();
  put "P8 empty hash iter    rc=" rc;
run;

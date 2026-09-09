/* BUG-hashofhashexplicit — NOTE-hashofhash's guard was IMPLICIT-form-only.

   A defineData'd name that is itself a declared hash object cannot be stored
   (Value is num|str; true hash-of-hash needs an object value type). The guard
   for that lived inside collectArgs' `out.items.len == 0` arm — the IMPLICIT
   `h.add()` spelling — so the EXPLICIT tag form `h.add(key: 1, data: inner)`
   walked past it, stored a SILENT numeric missing and exited 0. A later find()
   then reported a HIT (rc 0) and handed back `inner=.`: a fabricated value at
   exit 0, the worst failure class here. The `dataset:` bulk load never calls
   collectArgs at all and was silent by the same hole.

   A hash of hashes IS documented SAS (Language Reference: Concepts), so this is an opensas GAP → rc 2,
   not a user error.

   THE POINT OF THE PUTs BELOW IS THE VALUE, NOT THE DIAGNOSTIC. Asserting only
   that an ERROR appears would have passed with the bug on the guarded spelling.
   Pre-fix stdout carried `nested add rc=0` and `nested find rc=0 inner=.`;
   post-fix the step halts at defineDone and neither line is ever emitted, so
   this golden pins that NO WRONG VALUE IS PRODUCED.

   The PROC PRINT above proves the guard DISCRIMINATES rather than blanket-
   rejecting: a hash object is declared in that step too, and the EXPLICIT
   key:/data: spelling is the one used, but the defineData'd name is an ordinary
   variable, so it must still work.

   One error, last (BUG-errhalt).
   expect-rc: 2 */

data _null_;
  length k 8 v 8;
  declare hash inner();
  declare hash h();
  h.defineKey("k");
  h.defineData("k", "v");
  h.defineDone();
  rc = h.add(key: 1, data: 1, data: 10);
  rc = h.add(key: 2, data: 2, data: 20);
  rc = h.output(dataset: "kept");
run;

proc print data=kept noobs;
run;

data _null_;
  length k 8;
  declare hash inner();
  declare hash h();
  h.defineKey("k");
  h.defineData("inner");
  h.defineDone();
  rc = h.add(key: 1, data: inner);
  put "nested add rc=" rc;
  rc = h.find(key: 1);
  put "nested find rc=" rc " inner=" inner;
run;

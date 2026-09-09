/* BUG-declaredobjnamevalue — a declared object's NAME used as a VALUE resolved
   to missing, silently, at exit 0.

   `declare hash inner();` makes `inner` an OBJECT REFERENCE, not a variable:
   SAS 9.4 Component Objects: Reference, Third Edition, printed p.12 — "The
   DECLARE statement tells the compiler that the object reference myhash is of
   type hash. At this point, you have declared only the object reference
   myhash." So the name has no numeric or character value to read, and
   `x = inner + 1;` is invalid SAS.

   opensas resolved it to numeric missing and exited 0 — a fabricated value, the
   worst failure class here (D-002). Found while fixing BUG-hashofhashexplicit
   (00d3cd1b), and MEASURED there to be general rather than hash-specific: the
   `h.add(key: 1, data: inner)` symptom that surfaced it is only one expression
   position among many, so the fix is at the ONE point where a bare name becomes
   a value (eval.zig's `.variable` arm), not at the `data:` slot.

   The volumes give no verbatim log text for this, so the BASIS for erroring at
   all is the house fail-loud rule; the doc settles only what is cited above,
   that the name is an object reference and not a value. rc 1, not 2: writing an
   object name where a value belongs is invalid user SAS (D-009b(ii)), so it
   does NOT go through failGap.

   THE POINT OF THE PUTs IN THE LAST STEP IS THE VALUE, NOT THE DIAGNOSTIC.
   Asserting only that an ERROR appears would pass with the bug still present.
   Pre-fix stdout carried `arith x=.` and `inner=.`; post-fix the step halts at
   the read and neither line is ever emitted, so this golden pins that NO WRONG
   VALUE IS PRODUCED.

   The two steps above prove the guard DISCRIMINATES rather than blanket-
   rejecting every name in a step that declares an object:
     - step 1 declares a hash AND a hash iterator, works them end to end, and
       computes with ordinary variables whose names merely RESEMBLE them;
     - step 2 uses h / hi / inner as ordinary variables — the objects list is
       per-step, so a name declared in a DIFFERENT step must not start erroring.

   One error, last (BUG-errhalt).
   expect-rc: 1 */

data kept;
  length k v 8;
  declare hash h();
  h.defineKey("k");
  h.defineData("k", "v");
  h.defineDone();
  k = 1; v = 10; rc = h.add();
  k = 2; v = 20; rc = h.add();
  declare hiter hi("h");
  rc = hi.first();
  put "iter first k=" k " v=" v;
  /* ordinary variables that only RESEMBLE the object names */
  hh = 5;
  h2 = hh + 1;
  hiter = 7;
  innermost = hh + hiter;
  put "controls hh=" hh " h2=" h2 " hiter=" hiter " innermost=" innermost;
  keep hh h2 hiter innermost;
  output;
run;

proc print data=kept noobs;
run;

data later;
  /* no DECLARE anywhere in this step: h / hi / inner are plain variables */
  h = 3;
  hi = 4;
  inner = 5;
  z = h + hi + inner;
  put "later step z=" z;
  output;
run;

proc print data=later noobs;
run;

data _null_;
  /* NO hash call anywhere — the root is general expression resolution */
  declare hash inner();
  x = inner + 1;
  put "arith x=" x;
  put inner=;
run;

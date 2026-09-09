/* GH#81 ISS-arrayinitnonconst: an ARRAY (or RETAIN) parenthesised
   initial-value-list takes CONSTANTS ONLY. SAS 9.4 DATA Step Statements printed
   p.24: "(initial-value-list) gives initial values for the corresponding
   elements in the array. The values for elements can be numbers or character
   strings. You must enclose all character strings in quotation marks."  The
   disambiguating example is printed p.26 Ex.3 —
   `array test2{*} $ a1 a2 a3 ('a','b','c');` — variable NAMES outside the
   parentheses, constants inside.

   Before the fix `array v[2](a1 a2);` parsed clean: it declared PHANTOM v1/v2
   seeded from an unevaluatable variable read (missing), left a1/a2 untouched,
   and exited 0 with an EMPTY stderr — the worst failure class. Now it is a LOUD
   user error (rc 1, D-009: invalid SAS, not an opensas gap).

   The ERROR text goes to stderr (asserted via captured diagnostics in
   parser.zig's test block); stdout below pins that every LEGAL constant form
   still works and that the bad step halts the job.
   expect-rc: 1 */

/* --- legal constant forms: all of these must keep working ---------------- */
data _null_;
  array v[2] (1 2);            /* plain numeric constants */
  array w[2] $ ("x" "y");      /* quoted char constants into a $ array */
  array n[3] (-1 0 1);         /* signed literals fold to constants */
  array r[4] (2*7 1 2);        /* `n*value` stays a REPEAT factor: 7 7 1 2 */
  array m[2] (. 5);            /* the missing literal is a constant */
  put "consts=" v1 v2 w1 w2 n1 n2 n3 r1 r2 r3 r4 m1 m2;
run;

/* A BARE (unparenthesised) member list is a variable REFERENCE list, not an
   initial-value list — untouched by this rule, with or without a trailing
   (init) group. */
data _null_;
  length a1 a2 $10;
  a1 = "before-a1"; a2 = "before-a2";
  array k[2] a1 a2;            /* k aliases a1/a2 */
  array j[2] b1 b2 (1 2);      /* member list AND inits — 1→b1, 2→b2 */
  k[1] = "p"; k[2] = "q";
  put "refs=" a1 a2 b1 b2;
run;

/* RETAIN keeps both its legal forms: a bare trailing value seeds every element,
   a parenthesised list binds positionally. */
data _null_;
  retain s 0;
  retain t u (1 2);
  put "retain=" s t u;
run;

/* --- the reject: a VARIABLE where only a constant is legal ---------------- */
data c6;
  length a1 a2 $10;
  a1 = "before-a1";
  a2 = "before-a2";
  array v[2](a1 a2);   /* ERROR here — parse stops, nothing below runs */
  v[1] = "p";
  v[2] = "q";
run;

proc print data=c6;    /* never reached */
run;

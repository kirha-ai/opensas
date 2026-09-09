/* BUG-scanmissingtype — SCAN is a CHARACTER function (SAS 9.4 Functions and
   CALL Routines: Reference, 5th ed., p.1462: "Returns the nth word from a
   character string"), so a no-match or an invalid count yields a BLANK
   CHARACTER value, not a numeric missing.

   The `put (x) ($char10.);` lines are the regression test proper: a $CHARw.
   write format applied to a NUMERIC value is a hard ERROR in this interpreter
   (rc 1), so if any arm below regressed to a numeric missing this fixture goes
   red on the rc pin, not just on a diff. Ten blanks is a PASS.

   GH#78 also claimed the argument order was inverted (character-list before
   count). It is not — `SCAN(string, count <, character-list <, modifier>>)` is
   correct and the tail of this fixture pins it. */
data _null_;
  length t $1;

  /* the reported shape: ':' lands in the count slot, so the count is invalid.
     SAS still NOTEs the invalid numeric data, but x stays CHARACTER. */
  x = scan("a:b:c", ":", 2);
  t = vtype(x);
  put "type_invalidcount=" t;
  put (x) ($char10.);
  put "|";

  /* every other no-match / invalid-count arm is character too */
  oob   = scan("a b c", 9);      /* count past the last word */
  zero  = scan("a b c", 0);      /* count 0 */
  neg   = scan("a b c", -9);     /* negative past the first word */
  huge  = scan("a b c", 1e19);   /* count too big to be an index */
  empty = scan("", 1);           /* empty source string */
  t = vtype(oob);   put "type_oob="   t;
  t = vtype(zero);  put "type_zero="  t;
  t = vtype(neg);   put "type_neg="   t;
  t = vtype(huge);  put "type_huge="  t;
  t = vtype(empty); put "type_empty=" t;
  put (oob)   ($char10.);
  put (zero)  ($char10.);
  put (neg)   ($char10.);
  put (huge)  ($char10.);
  put (empty) ($char10.);
  put "|";

  /* regression: the correct 3-arg and 4-arg calls still work, count SECOND */
  a  = scan("a:b:c", 1, ":");
  b  = scan("a:b:c", 2, ":");
  c  = scan("a:b:c", -1, ":");
  w2 = scan("a b c", 2);
  m4 = scan("a.b,c", 2, ".,", "o");
  put "a=" a " b=" b " c=" c " w2=" w2 " m4=" m4;
run;

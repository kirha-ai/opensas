/* GAP-atexpression-put: PUT `@(expression)` column pointer — the PUT twin of
   INPUT's form landed by GAP-atexpression.

   Statements printed p.269 (PDF index = printed + 11; the entry sits on pdf
   280, whose footer reads 'PUT Statement 269'): '@(expression) moves the
   pointer to the column that is given by the value of expression. Range: a
   positive integer. Tip: If the value of expression is not an integer, SAS
   truncates the decimal value and uses only the integer value. If it is zero,
   the pointer moves to column 1.'

   WORDING NOTE — the PUT entry drops the word "negative" that INPUT's p.168
   entry and PUT's OWN `@numeric-variable` sibling one entry above both carry
   ('If n is zero or negative, the pointer moves to column 1'). That is an
   omission, not a different rule: both PUT entries declare 'Range a positive
   integer', and every pointer control on p.269-270 floors at column 1 — even
   `+numeric-variable`, which moves BACKWARD, says 'If the current column
   position becomes less than 1, the pointer moves to column 1'. So negative
   clamps to 1 here too, through io.zig's ONE clampCol that `@n`,
   `@numeric-variable` and INPUT's `@(expression)` already share. The literal
   `@n` PUT control below is pinned on the same shape so the two forms cannot
   drift apart.

   PREMISE CORRECTED: PUT has only TWO `@` column-pointer forms in opensas —
   the literal `@n` and (now) `@(expression)`. p.269's `@numeric-variable`
   entry (`a=15; put @a name $10.;`) is a SEPARATE, still-open gap: it fails
   LOUD at parse, and that loud failure is pinned in parser.zig's in-file test
   so it can never start silently meaning something else. `@(n)` is the
   supported spelling of the same thing and is the runtime-value control here.

   `@(character-expression)` (SAS's other parenthesised form, the string
   search) stays unimplemented and ERRORs loud on BOTH statements — pinned in
   exec.zig's in-file test via the captured diagnostics reporter, since the
   corpus diffs stdout only. */

data _null_;                    /* @(1+2) → column 3 */
  put @(1+2) "pos";
run;

data _null_;                    /* n-1 with n=1 → 0 → clamps to column 1 */
  n = 1;
  put @(n-1) "zero";
run;

data _null_;                    /* n-5 with n=1 → -4 → clamps to column 1 */
  n = 1;
  put @(n-5) "neg";
run;

data _null_;                    /* p.269's own example: `b=5; put @(b*3) name $10.;`
                                   b*3 = 15 → the value starts at column 15.
                                   The trailing "|" makes the $10. field width
                                   visible and keeps the golden free of
                                   trailing blanks. */
  b = 5;
  name = "Watson";
  put @(b*3) name $10. "|";
run;

data _null_;                    /* literal control for the line above: @15 must
                                   produce a BYTE-IDENTICAL line to @(b*3) */
  name = "Watson";
  put @15 name $10. "|";
run;

data _null_;                    /* non-integer truncates: 17/3 = 5.67 → column 5 */
  put @(17/3) "trunc";
run;

data _null_;                    /* the pointer moves PER PUT: same statement, two
                                   values of the same expression across iterations */
  do b = 1 to 3;
    put @(b*2) "step";
  end;
run;

data _null_;                    /* mid-line: an @(expr) after a value positions the
                                   NEXT item and suppresses the list separator */
  k = 4;
  put "ab" @(k*3) "cd";
run;

/* controls: the literal `@n` and the runtime `@(n)` must agree on the same shape */
data _null_;
  put @3 "cn";
run;

data _null_;
  n = 3;
  put @(n) "cv";
run;

data _null_;                    /* negative through the runtime form → column 1 */
  n = -4;
  put @(n) "cvn";
run;

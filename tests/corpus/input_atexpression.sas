/* GAP-atexpression + NOTE-atexprclamp: INPUT `@(expression)` column pointer.
   Statements printed p.168: '@(expression) moves the pointer to the column
   that is given by the value of expression … If it is zero or negative, the
   pointer moves to column 1' (a non-integer is truncated first). The value
   routes through the SAME clamp `@n` and `@numeric-variable` already use
   (io.zig clampCol) — both are pinned alongside as controls so the three
   forms cannot drift apart. `@(character-expression)` (the string-search
   form) stays unimplemented and ERRORs loud — pinned in io.zig's in-file
   test via the captured diagnostics reporter (corpus diffs stdout only). */

data positive;                 /* @(1+2) → column 3 */
  input @(1+2) x $3.;
  put "pos=" x;
datalines;
abcde
;
run;

data zero;                     /* n-1 with n=1 → 0 → clamps to column 1 */
  n = 1;
  input @(n-1) x $3.;
  put "zero=" x;
datalines;
xyz
;
run;

data negative;                 /* n-5 with n=1 → -4 → clamps to column 1 */
  n = 1;
  input @(n-5) x $3.;
  put "neg=" x;
datalines;
qwe
;
run;

data computed;                 /* a variable computed earlier in the same
                                  step moves the pointer — p.168's own
                                  example shape `b=5; input @(b*3) name $10.;` */
  b = 2;
  input @(b*3) x $3.;          /* → column 6 */
  put "comp=" x;
datalines;
12345abc
;
run;

data trunc;                    /* non-integer truncates: 17/3 = 5.67 → column 5 */
  input @(17/3) x $3.;
  put "trunc=" x;
datalines;
1234abc
;
run;

/* controls: `@n` and `@numeric-variable` on the same shapes must agree */
data ctrl_n;
  input @6 x $3.;
  put "cn=" x;
datalines;
12345abc
;
run;

data ctrl_var;
  n = 6;
  input @n x $3.;
  put "cv=" x;
datalines;
12345abc
;
run;

data ctrl_varneg;              /* negative @var — the pre-existing clamp (BUG-atcol0crash) */
  n = -4;
  input @n x $3.;
  put "cvn=" x;
datalines;
qwe
;
run;

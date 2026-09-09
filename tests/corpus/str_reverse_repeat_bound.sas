/* Boundary pins for two char functions not covered elsewhere:
   - REVERSE reverses ALL characters INCLUDING trailing blanks, so trailing
     blanks become LEADING blanks (SAS 9.4 Functions Ref, REVERSE). The already-
     banked str_fns2 only reverses a blank-free literal, so this fixture pins the
     trailing-blank case.
   - REPEAT(str, n) returns str repeated n ADDITIONAL times (n+1 copies total).
     n=0 is the boundary: exactly one copy, NOT the empty string. str_fns2 covers
     n=2; this pins the n=0 edge. */
data _null_;
  rv = reverse("abc  ");   /* 5 chars: a b c _ _  ->  _ _ c b a */
  r0 = repeat("x", 0);     /* n=0 -> 1 copy -> "x" */
  r1 = repeat("ab", 1);    /* n=1 -> 2 copies -> "abab" */
  put "rv=[" rv "]";
  put "r0=[" r0 "]";
  put "r1=[" r1 "]";
run;

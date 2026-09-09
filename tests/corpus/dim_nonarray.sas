/* BUG-dimnonarray: DIM/HBOUND/LBOUND of a NON-array variable (a plain scalar)
   used to silently return the variable's VALUE as the "bound" (charfns'
   generic handler assumed the parser had replaced an array name with its
   element count; a scalar name was never replaced and sailed through).
   SAS 9.4: the argument must be an ARRAY name — a compile-time ERROR. Now the
   parser fails loud when the name isn't a registered array. The ERROR is on
   stderr (asserted via captured diagnostics in parser_expr.zig's test);
   stdout pins that step 1's REAL array bounds still fold, and that step 2
   (the bad dim) never runs.
   expect-rc: 1 */

data _null_;
  array a{5} a1-a5;
  d = dim(a); h = hbound(a); l = lbound(a);
  put d= h= l=;   /* a real array: 5 / 5 / 1 */
run;

data _null_;
  x = 5;
  d = dim(x);     /* ERROR: x is a scalar, not an ARRAY name — parse fails here */
  put 'never-reached';
run;

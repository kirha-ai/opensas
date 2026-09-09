/* GAP-putcolptr: PUT relative column pointer `+n` and line pointer `#n`.
   `+n` moves the pointer n columns right (n blanks); `#n` moves to output
   line n. `@n` (absolute) already worked; these are its siblings. */
data _null_;
  a = "X"; b = "Y"; c = "Z";
  /* +n relative: X, +3 -> 3 blanks, Y, +2 -> 2 blanks, Z */
  put a +3 b +2 c;
  /* #n line pointer: a on line 1, b on line 2, c on line 3 */
  put a #2 b #3 c;
  /* @n absolute still works alongside +n */
  put a @10 b;
run;

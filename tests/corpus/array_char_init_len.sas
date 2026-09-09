/* BUG-arraycharinitlen: an explicit `$len` on a CHARACTER array is authoritative —
   an init constant longer than it is TRUNCATED to it (not silently re-spec'd to the
   constant's length), exactly like an assignment through the array. Without a `$len`
   the element length is inferred from the constants (unchanged). */
data _null_;
  array a{2} $3 ('xxxxx' 'yy');   /* 'xxxxx' -> 'xxx' (truncated to 3), 'yy' kept */
  la1 = length(a1); la2 = length(a2);
  put "explicit_len=" a1 "|" a2 "|" la1= la2=;

  array b{2} $ ('aaaa' 'b');      /* no $len: length inferred from longest constant */
  lb1 = length(b1); lb2 = length(b2);
  put "inferred_len=" b1 "|" b2 "|" lb1= lb2=;
run;

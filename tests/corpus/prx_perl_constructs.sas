/* doc-finder tick133 (BUG-prxconstruct): PRXPARSE silently mis-compiled common
   Perl/PCRE constructs instead of honoring them or failing loud. Lookahead
   (?=...)/(?!...), named groups (?<name>...), the /s (dotall) and /m (multiline)
   modifiers, and POSIX classes [[:name:]] are all documented SAS 9.4 PRX
   features; opensas parsed the metachars as literals / dropped the modifier, so
   the pattern silently matched the WRONG thing. prxmatch returns the 1-based
   match start (0 = none). a-d expected = real SAS (doc-finder verified); e-j
   follow directly from the documented semantics (/m rows per the finding). */
data _null_;
  a=prxmatch('/foo(?=bar)/', 'foobar');    /* lookahead ok -> 1        */
  b=prxmatch('/foo(?=bar)/', 'foobaz');    /* lookahead fails -> 0     */
  c=prxmatch('/(?<y>\d{4})/', 'yr 2026');  /* named group -> col 4     */
  d=prxmatch('/a.b/s', 'a' || '0A'x || 'b'); /* /s: . matches LF -> 1  */
  e=prxmatch('/foo(?!bar)/', 'foobaz');    /* neg lookahead ok -> 1    */
  f=prxmatch('/foo(?!bar)/', 'foobar');    /* neg lookahead fails -> 0 */
  g=prxmatch('/^b/m', 'a' || '0A'x || 'b');  /* /m: ^ after LF -> 3    */
  h=prxmatch('/c$/m', 'abc' || '0A'x || 'd');/* /m: $ before LF -> 3   */
  i=prxmatch('/^b/', 'a' || '0A'x || 'b');   /* no /m -> 0             */
  j=prxmatch('/[[:digit:]]+/', 'ab123');   /* POSIX class -> col 3     */
  put "la_pos=" a;
  put "la_neg=" b;
  put "named=" c;
  put "dotall=" d;
  put "nla_pos=" e;
  put "nla_neg=" f;
  put "ml_start=" g;
  put "ml_end=" h;
  put "ml_off=" i;
  put "posix=" j;
run;

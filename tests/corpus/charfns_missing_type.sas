/* BUG-charfnsmissingtype: a SAS CHARACTER function must hand back the CHARACTER
   missing — a blank — on every give-up path. Several returned a NUMERIC missing
   instead, which flips the receiving variable's TYPE, and that is not cosmetic:
   `put (x) ($char10.);` then dies with "The character format $char10. cannot be
   used with a numeric value" and the run exits 1 where SAS exits 0.

   Every function below is `Categories: Character` in the SAS 9.4 Functions and
   CALL Routines: Reference — BYTE p.282 (Range 0-255), COLLATE p.521
   ("end-position must be larger than start-position"), HASHING p.975,
   HASHING_HMAC p.978, SUBPAD p.1529 (position "is a positive integer") — so
   p.5's general rule, "sets the result to a missing value", means BLANK here.
   Same class as BUG-scanmissingtype (SCAN, COMPRESS).

   VTYPE pins the type; the $CHAR10. PUTs are the symptom itself — each was an
   ERROR before the fix, and the whole program exits 0 now. */
data _null_;
  length tag $1;

  /* BYTE — outside the documented 0-255 range, and a missing argument */
  b1 = byte(-1);    tag = vtype(b1); put 'byte(-1)      vtype=' tag;
  b2 = byte(999);   tag = vtype(b2); put 'byte(999)     vtype=' tag;
  b3 = byte(.);     tag = vtype(b3); put 'byte(.)       vtype=' tag;

  /* COLLATE — bad start, end below start, end out of range, zero-length run */
  c1 = collate(-1);       tag = vtype(c1); put 'collate(-1)   vtype=' tag;
  c2 = collate(65, 60);   tag = vtype(c2); put 'collate(65,60) vtype=' tag;
  c3 = collate(65, 999);  tag = vtype(c3); put 'collate(65,999) vtype=' tag;
  c4 = collate(65, , 0);  tag = vtype(c4); put 'collate(65,,0) vtype=' tag;

  /* HASHING / HASHING_HMAC — an unrecognised method still returns hex, i.e. char */
  h1 = hashing('nosuchmethod', 'abc');           tag = vtype(h1); put 'hashing bad   vtype=' tag;
  h2 = hashing_hmac('nosuchmethod', 'k', 'abc'); tag = vtype(h2); put 'hashing_hmac bad vtype=' tag;

  /* SUBPAD — missing position, and a position/length too big for an integer.
     The NONPOSITIVE position is the interesting one: it routes through the
     shared domain-error path (NOTE + _ERROR_=1, NOTE-subpadinvpos), which
     returns a numeric missing for its ~40 numeric callers. SUBPAD needed the
     character flavour of it, not a blind edit of the shared helper. */
  s1 = subpad('abcdef', .);       tag = vtype(s1); put 'subpad miss   vtype=' tag;
  s2 = subpad('abcdef', 1e19);    tag = vtype(s2); put 'subpad hugepos vtype=' tag;
  s3 = subpad('abcdef', 1, 1e19); tag = vtype(s3); put 'subpad hugelen vtype=' tag;
  s4 = subpad('abcdef', 0, 3);    tag = vtype(s4); put 'subpad pos0   vtype=' tag;
  s5 = subpad('abcdef', -2, 3);   tag = vtype(s5); put 'subpad posneg vtype=' tag;
  put 'subpad pos0 _error_=' _error_;   /* the domain path still flags, per p.5 */
  _error_ = 0;

  /* the symptom: a character format over each result. Numeric missings made
     every one of these a hard ERROR. */
  put (b1) ($char10.);
  put (c2) ($char10.);
  put (h1) ($char10.);
  put (h2) ($char10.);
  put (s1) ($char10.);
  put (s4) ($char10.);

  /* the good paths are untouched — value AND type */
  g1 = byte(80);              put 'byte(80)=' g1;      /* p.282's own example */
  g2 = collate(65, 67);       put 'collate(65,67)=' g2;
  g3 = collate(65, , 3);      put 'collate(65,,3)=' g3;
  g4 = hashing('md5', 'abc'); put 'hashing md5=' g4;
  g5 = subpad('abcdef', 2, 3);  put 'subpad(2,3)=[' g5 ']';
  g6 = subpad('abc', 2, 5);     put 'subpad(2,5)=[' g6 ']';  /* blank-padded past the end */
run;

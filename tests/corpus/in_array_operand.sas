/* GAP-inoperators (2/3): the right operand of IN may be an ARRAY NAME instead
   of a parenthesised value list — "You can also use the IN operator to search
   an array" (Language Reference: Concepts p.128 numeric, p.130 character). The test is membership over
   the array's ELEMENTS, so it is the same OR-of-equalities the list form
   desugars to; element order cannot matter and a NOT IN is the AND of the
   inequalities.

   The first two steps pin the shape Language Reference: Concepts illustrates at
   Example Code 6.2 / 6.3: probe a value the array lacks (0), assign it to one
   element, probe again (1) — once for a numeric array, once for a character
   array. 6.2's `array a{10} (2*1:5)` repeat-of-a-range init is not used here —
   that init syntax is a separate gap, not this one.

   Edge cases pinned below: a probe that matches nothing, a _temporary_ array
   (anonymous members), a missing probe against a missing element, and IN: over
   an array. `x in <name-that-is-not-an-array>` stays the loud "expected '('
   after IN", and an `array v{*} _numeric_` right operand is loud too (its
   members are a runtime fact) — both are captured-diagnostics tests in
   parser_expr.zig. */

/* numeric array: probe absent, then present after an element assignment */
data _null_;
   array codes{10} (3 6 9 12 15 3 6 9 12 15);
   probe=42;
   found = probe in codes;
   put found=;
   codes{5} = 42;
   found = probe in codes;
   put found=;
run;

/* character array: all-blank members, then one set to the probe */
data _null_;
   array tags{5} $ (5*'');
   probe='q7';
   found = probe in tags;
   put found=;
   tags{5} = 'q7';
   found = probe in tags;
   put found=;
run;

data _null_;
  array doses{5} (25 50 75 100 125);
  array sites{3} $2 ('LY','MZ','NP');
  array scratch{3} _temporary_ (4 5 6);
  hit   = 75 in doses;      /* middle element */
  first = 25 in doses;      /* first element */
  miss  = 99 in doses;
  chit  = 'MZ' in sites;
  cmiss = 'ZZ' in sites;
  nhit  = 99 not in doses;  /* NOT IN = AND of the inequalities */
  nmiss = 75 not in doses;
  thit  = 5 in scratch;     /* _temporary_ members are searchable */
  tmiss = 2 in scratch;
  put hit= first= miss= chit= cmiss= nhit= nmiss= thit= tmiss=;
run;

data _null_;
  array gaps{3} (4 . 8);
  array names{2} $4 ('LUKA','PERO');
  hasmiss = . in gaps;      /* missing = missing, so a missing probe is found */
  nomiss  = 6 in gaps;
  pfx     = 'LU' in: names;  /* IN: over an array — prefix compare per element */
  nopfx   = 'QQ' in: names;
  put hasmiss= nomiss= pfx= nopfx=;
run;

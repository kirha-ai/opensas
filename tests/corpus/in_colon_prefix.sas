/* GAP-inoperators (3/3): `IN:` — the colon prefix-match modifier on IN. "You
   can add a colon (:) modifier to any of the operators to compare only a
   specified prefix of a character string" (Language Reference: Concepts p.127); p.130 names the "IN:
   comparison" beside the "EQ: comparison" in the zero-length rule. Each
   membership test therefore truncates BOTH operands to the shorter one's
   length — the very same prefix compare `=:` already uses, so the two colon
   forms agree by construction, including the rule that a zero-length value
   never matches (Language Reference: Concepts p.130: "The result always evaluates to 0").

   `x in: (1:3)` — the colon modifier over the M:N integer-range form — is a
   loud parse error (captured-diagnostics test in parser_expr.zig): the doc
   defines the prefix compare for character strings only. */
data _null_;
  v = 'ABCD';
  y1 = v in: ('AB','ZZ');    /* longer value truncated to the shorter operand */
  y2 = v in: ('ZZ','QQ');    /* no element shares the prefix */
  y3 = v in  ('AB','ZZ');    /* plain IN still compares in full → 0 */
  y4 = v not in: ('AB');     /* NOT IN: is the negation of the prefix match */
  y5 = 'AB' in: ('ABCD');    /* the SHORTER operand may be on either side */
  y6 = '' in: ('AB');        /* zero-length never matches (Language Reference: Concepts p.130) */
  y7 = v in: ('ABCD');       /* equal lengths = a plain equality */
  put y1= y2= y3= y4= y5= y6= y7=;
  /* the space-separated list form and the mnemonic-free WHERE-free surface
     keep working under the modifier */
  y8 = v in: ('QQ' 'AB');
  put y8=;
  /* IN: agrees with the sibling =: on the same pair (one shared compare) */
  agree = (y5 = ('AB' =: 'ABCD')) and (y6 = ('' =: 'AB'));
  put agree=;
run;

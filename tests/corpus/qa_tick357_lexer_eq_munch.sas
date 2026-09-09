/* QA tick357 — GAP-inoperators (14928a2c) taught the lexer a two-char munch
   starting at `=` (the legacy `=<` / `=>` spellings of LE / GE, Language Reference: Concepts p.127
   Table 6.4 footnotes 2 and 3). A maximal-munch rule on a character as common
   as `=` is the classic way to break a DISTANT, unrelated expression, and the
   damage would show up nowhere near the operator that caused it.

   This is the NEGATIVE-SPACE control: every neighbouring shape where `=` sits
   next to `<`, `>`, `-`, `*` or a comment and must NOT be munched. The legacy
   pair itself is already covered by cmp_legacy_lege; what is pinned here is
   everything the munch must keep its hands off. */
data d;
  input x k $;
datalines;
1 a
2 b
3 c
;
run;

data w;
  set d;
  /* `=-` : assignment of a negated value, NOT an operator. Three spacings. */
  neg_tight = -1;
  neg_expr  = -x;
  neg_sp    = -2;
  /* `=*` : the sounds-like pair — parser_expr peeks `.eq` + `.star`, so the
     munch must not consume it */
  snd = (k =* "a");
  /* a SPACED `= <` is two tokens: SAS requires the legacy pair to be adjacent */
  spaced = (x = 1) < 1;
  /* `=` immediately followed by a comment, and a comment CONTAINING `=<` */
  cmt = /* c */ 7;
  /*=<*/ after_cmt = 8;
  /* the symbolic comparisons that share a first or second character with the
     new pair — none may shift */
  le_mod = (x <= 2);
  ge_mod = (x >= 2);
  ne_hat = (x ^= 2);
  ne_til = (x ~= 2);
  min_op = (x >< 2);
  max_op = (x <> 2);
  /* `-` runs that follow an operator, where a greedy munch would misread */
  sub_neg = x - -1;
  sub_tight = x - (-1);
  mul_neg = x * -1;
  pow_neg = x ** -1;
run;
proc print data=w noobs;
  var x neg_tight neg_expr neg_sp snd spaced cmt after_cmt;
run;
proc print data=w noobs;
  var le_mod ge_mod ne_hat ne_til min_op max_op sub_neg sub_tight mul_neg pow_neg;
run;

/* a WHERE clause using the MODERN spellings must stay legal — the loudness the
   landing added is keyed on the legacy spelling carried in token.text, so an
   empty-text `.le`/`.ge` must pass through untouched */
data ww;
  set d;
  where x >= 2;
run;
proc print data=ww noobs; run;

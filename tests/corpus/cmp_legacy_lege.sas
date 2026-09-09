/* GAP-inoperators (1/3): `=<` and `=>` are the LEGACY spellings of LE and GE —
   `=<` means <= and `=>` means >=. SAS 9.4 still accepts both "for
   compatibility with previous releases of SAS" (Language Reference: Concepts p.127, Table 6.4
   footnotes 2 and 3). The lexer emits the SAME .le/.ge tokens as `<=`/`>=`, so
   precedence, chaining and the mnemonics are shared by construction; this
   fixture pins the surface and the three things a maximal-munch change could
   break:
     - `x =-1` is still an assignment of -1, not a comparison
     - `=*` (sounds-like) still lexes as its own `.eq`+`.star` pair
     - `<=` / `>=` are untouched
   The loud half of the same footnotes — the legacy spellings are NOT valid in
   a WHERE clause — is a captured-diagnostics test in parser_expr.zig, since a
   step ERROR would syntax-check-skip the rest of this file. */
data _null_;
  x = 3;
  le5 = x =< 5;   le3 = x =< 3;   le2 = x =< 2;
  ge5 = x => 5;   ge3 = x => 3;   ge2 = x => 2;
  put le5= le3= le2= ge5= ge3= ge2=;
  /* same operator, so chained comparison applies (D-013): a =< x =< b is
     (a<=x) and (x<=b), not ((a<=x)<=b) */
  chain_in  = (1 =< x =< 5);
  chain_out = (1 =< x =< 2);
  put chain_in= chain_out=;
  /* the symbol pair agrees with the mnemonic and with the modern spelling */
  same = (le5 = (x le 5)) and (ge3 = (x ge 3)) and (le5 = (x <= 5)) and (ge3 = (x >= 3));
  put same=;
  /* character operands compare like any other LE/GE */
  cle = ('abc' =< 'abd');
  cge = ('abc' => 'abd');
  put cle= cge=;
  /* neighbours that must NOT be swallowed by the new two-char munch */
  neg =-1;
  sndx = ('Smith' =* 'Smyth');
  put neg= sndx=;
  if x => 3 then put 'IF-GE TAKEN';
  if x =< 2 then put 'IF-LE TAKEN — WRONG';
                else put 'IF-LE SKIPPED';
run;

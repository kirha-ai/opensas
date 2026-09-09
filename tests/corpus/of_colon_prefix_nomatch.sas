/* GAP-ofcolonprefix: a prefix that matches NO variable. The doc (Language Reference: Concepts
   printed p.70 Table 4.5) settles only the matching rule, not the empty
   case — so D-002 and the tree's own special-list precedent ("ARRAY {s}:
   special list matched no variables", eval.zig) decide: a loud ERROR and a
   missing result, never a silent zero-argument call. rc 1, not 2 — a
   typo'd prefix is the user's error (D-009), same class as an uninitialized
   variable reference.
   expect-rc: 1 */
data _null_;
  y = 1;
  s = sum(of zz:);
  put "s=" s;
run;

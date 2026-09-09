/* GAP-hashnewhiter (Language Reference: Concepts p.624): `hi = _new_ hiter('h');` — the two-step
   iterator instantiation — must produce the identical object the
   `declare hiter hi('h');` one-step form produces. Pinned side by side. */
data _null_;
  length k d 8;
  declare hash h();
  h.defineKey('k'); h.defineData('k','d'); h.defineDone();
  k=1; d=10; h.add(); k=2; d=20; h.add();
  declare hiter hi;
  hi = _new_ hiter('h');
  rc=hi.first(); put rc k d;
  rc=hi.next();  put rc k d;
run;
data _null_;
  length k d 8;
  declare hash h();
  h.defineKey('k'); h.defineData('k','d'); h.defineDone();
  k=1; d=10; h.add(); k=2; d=20; h.add();
  declare hiter hi('h');
  rc=hi.first(); put rc k d;
  rc=hi.next();  put rc k d;
run;

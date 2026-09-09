/* BUG-hashoutputnametrim (GAP-hashmed-tick293 F7): h.output(dataset: <expr>)
   TRIMS the computed member name. nm is $8, so 'w'||nm arrives blank-padded —
   pre-fix the member was literally 'woo     ', created at rc=0 and UNREACHABLE
   by any later step. The options branch of the same function already trimmed
   (two paths, one function); the plain branch now agrees. The fail-loud halves
   (invalid member name rc=1; defineData of a nonexistent variable, p.613) are
   pinned by the BUG-hashoutputnametrim/BUG-hashdefinenovar exec.zig tests —
   their ERRORs trip the run-level errhalt, so they cannot share this fixture. */
data _null_;
  length k d 8 nm $8;
  declare hash h();
  h.defineKey('k'); h.defineData('k','d'); h.defineDone();
  k=1; d=10; h.add();
  nm='oo';
  rc = h.output(dataset: 'w' || nm);
  put 'concat rc=' rc;
run;
proc print data=woo noobs; run;

/* blanks before the options paren trim too ('wo2  (where=…)' → member wo2) */
data _null_;
  length k d 8;
  declare hash h();
  h.defineKey('k'); h.defineData('k','d'); h.defineDone();
  k=1; d=10; h.add(); k=2; d=20; h.add();
  rc = h.output(dataset: 'wo2  (where=(k>1))');
  put 'opts rc=' rc;
run;
proc print data=wo2 noobs; run;

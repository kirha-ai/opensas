/* BUG-hashunknownarg + BUG-hashoutputdsopt (tick261 F1/F2):
   F2: h.output(dataset:'fout(where=(k>1))') splits member(options) — the
       where= filter APPLIES (was: the parenthesized string became the member
       name verbatim, filter silently dropped, rc=0).
   F1: a misspelled constructor tag (`odered:`) logs a loud ERROR instead of
       silently leaving a default hash. A step ERROR poisons later steps
       (syntax-check mode, BUG-errhalt), so the typo step comes LAST; the
       captured-diagnostics half is asserted in exec.zig.
   AUDIT-errhaltclass (golden MOVED here, deliberately): the typo step used to
       print 'typo step still ran' — it reported the ERROR and then executed the
       whole step on a DEFAULT hash the program never asked for. The ERROR class
       of Language Reference: Concepts printed p.174-175 stops the step, so that line is gone and the
       step now emits NOTHING. Pinning the silence is the point: asserting only
       the ERROR would pass with the bug still in place.
   Positive controls first: a valid ordered hash and a plain output work.
   expect-rc: 1 */
data _null_;
  declare hash h2(ordered:'a'); /* valid tag — sorted output */
  h2.defineKey('k'); h2.defineData('k','v'); h2.defineDone();
  k=2; v='two'; h2.add();
  k=1; v='one'; h2.add();
  k=3; v='three'; h2.add();
  rc = h2.output(dataset:'plain'); /* no options — all rows, key order */
  put 'plain rc=' rc;
run;
data _null_;
  declare hash h();
  h.defineKey('k'); h.defineData('k','v'); h.defineDone();
  k=1; v='one'; h.add();
  k=2; v='two'; h.add();
  k=3; v='three'; h.add();
  rc = h.output(dataset:'fout(where=(k>1))'); /* only k=2,3 survive */
  put 'opt rc=' rc;
run;
data _null_; set plain; put 'plain ' k= v=; run;
data _null_; set fout; put 'fout ' k= v=; run;
/* F1 LAST: the ERROR is in the log and the step STOPS there — the PUT below
   never runs, so this fixture ends with the `fout` lines above. */
data _null_;
  declare hash hbad(odered:'a'); /* typo of ordered: — loud ERROR, step stops */
  hbad.defineKey('k'); hbad.defineData('k'); hbad.defineDone();
  k=1; hbad.add();
  put 'typo step still ran';
run;

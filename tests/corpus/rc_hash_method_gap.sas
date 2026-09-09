/* GAP-gapsexitingone §5c — the hash-method catch-all was SPLIT, not re-tagged.

   SETCUR is in the SAS 9.4 Component Objects reference's own dictionary of
   hash language elements (printed p.23 TOC), so `h.setcur()` is valid SAS we
   have not written: an opensas GAP → rc 2. Its typo twin lives in
   rc_hash_method_typo.sas and must STAY rc 1 — re-tagging the whole catch-all
   would have told a user who mistyped a method name to file an opensas issue.

   The PROC PRINT proves the split discriminates: the implemented methods
   (defineKey/defineData/defineDone/add/output) still run and write the table.
   One error, last (BUG-errhalt).
   expect-rc: 2 */
data _null_;
  length k 8 v 8;
  declare hash h();
  h.defineKey("k");
  h.defineData("k", "v");
  h.defineDone();
  k = 1; v = 10; rc = h.add();
  k = 2; v = 20; rc = h.add();
  rc = h.output(dataset: "kept");
run;

proc print data=kept noobs;
run;

data _null_;
  length k 8 v 8;
  declare hash h();
  h.defineKey("k");
  h.defineData("v");
  h.defineDone();
  rc = h.setcur();
run;

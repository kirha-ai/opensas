/* GAP-ebnfrcwrongclass (libname_option row): the LIBNAME option catch-all's
   message NAMED the option but exited rc 1 — "your SAS is broken" — even for
   DOCUMENTED options real SAS 9.4 runs clean. Those are OUR gaps: NAMED rc 2
   (D-009/D-009b(i)), message byte-identical (the isFreqTablesGapOption split
   shape). The documented, clean-in-real-SAS, unimplemented set:
     - INENCODING=/OUTENCODING= — Procedures Guide === pdf 582/583 ===
       (printed pp. 532-533): the CVP example's own
       LIBNAME outlib 'SAS-library' outencoding="..."; is shown assigned CLEAN
       on "Engine: V9"; opensas does no transcoding.
     - CVPMULTIPLIER= — Procedures Guide printed p.1566 (=== pdf 1616 ===),
       the CVP family's LIBNAME option (implies the CVP engine in real SAS).
   NOT in the set (stay the rc-1 typo class, pinned by the captured test in
   src/main.zig): a typo (`bogusopt`, `acces`), and plain `cvp=` — the docs
   document the CVP ENGINE (Statements Ref printed p.221; the engine arm
   already gaps it at rc 2) but no `CVP=` LIBNAME OPTION, so the tick431
   row's literal premise does not hold and `cvp=yes` is NOT reclassed.
   The outencoding= arm fires in the parseLibnames pre-pass.
   expect-rc: 2 */
libname t "nowhere" outencoding="utf-8";
data _null_;
  put "unreached";
run;

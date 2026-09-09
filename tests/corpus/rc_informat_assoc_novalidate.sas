/* BUG-informatstmtnovalidate — NOT-A-DEFECT, pinned so the next dev does not
   "fix" it. A BARE `informat x zzzbogus99.;` association that nothing ever
   reads through is accepted at rc 0, and that is CONFORMANT with what the
   carried volumes state:
   - The Statements reference's INFORMAT entry (printed p.161-164, pdf 173-176;
     stated offset +12, 161+12=173 confirmed against the "INFORMAT Statement
     161" footer) and FORMAT entry (printed p.111-115) state NO name-validation
     rule for the association itself — the volumes are silent on compile-time
     checking here.
   - The only error rule the Formats and Informats Reference prints is
     USE-triggered: "If you execute a program that cannot locate a user-defined
     format ... FMTERR: SAS produces an error that causes the current DATA or
     PROC step to stop processing" (format half printed p.9, pdf 22; informat
     twin printed p.546, pdf 559 — both at stated offset +13, footers
     "Definitions for Dates, Times, and Intervals 9" / "546 Chapter 3").
     Every USE of an unknown informat in opensas IS loud at rc 1, pinned by
     rc_informat_bogus_typo.sas (list), rc_informat_negparen_typo.sas
     (direction-sensitive), rc_informat_unimpl_gap.sas (rc-2 gap arm) and
     informat_char_unknown.sas (char, step-halting).
   - D-009b corollary (internal consistency, no citation needed): the
     write-side twin `format y zzzbogus99.;` is measured silent at association
     and loud at first use (rc_fmt_bogus_typo.sas) — both statements defer
     name validation to first use SYMMETRICALLY, so the read side deferring
     too is the tree's settled shape. Making only the INFORMAT statement loud
     at compile would CREATE the asymmetry, not remove one.
   zzzbogus99 is in NEITHER re-derived 9.4 dictionary (format.zig doc_fmt_* /
   doc_inf_* — grep confirms), so this name can never flip direction.
   The PROC PRINT (var x; keeps it off y's bogus FORMAT, whose RENDER is a
   loud use by design) proves the step ran and produced data — a future
   compile-time validator on either statement flips this fixture rc 0 -> rc 1
   and reddens. Mutation-verified: a validation guard added to exec.zig's
   .informat association arm reddens this fixture (and nothing else in the
   pin's family); reverted.
   expect-rc: 0 */
data b;
  informat x zzzbogus99.;
  format y zzzbogus99.;
  x = 1;
  y = 2;
run;
proc print data=b;
  var x;
run;

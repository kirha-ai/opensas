/* BUG-sortseqbaresuperset — `options sortseq=linguistic(<collating-options>)`
   is a GAP (rc 2), not a user error. This fixture was created one commit
   earlier by BUG-rcsplitmembership F2 pinning rc 1, and F2 WAS WRONG on this
   one value; the pin is corrected here rather than deleted, so the reasoning
   stays in the tree.

   F2 relied on Base SAS 9.4 Procedures Guide printed p.2415 (`=== pdf 2464 ===`),
   PROC SORT SORTSEQ=, Restrictions: "The SORTSEQ=LINGUISTIC option is available
   only on the PROC SORT SORTSEQ= option and is not available for the system
   option SORTSEQ." THAT SENTENCE IS STALE. The same chapter, printed p.2403
   (`=== pdf 2452 ===`), says: "Starting in the third maintenance release of
   SAS 9.4, you can specify linguistic collation using the SORTSEQ= option in
   the SQL procedure and by specifying the SORTSEQ=LINGUISTIC system option."
   — a DATED feature statement, so the restriction describes the pre-M3 state.
   The SQL Procedure User's Guide printed p.261 (`=== pdf 276 ===`) corroborates
   twice more: "If LINGUISTIC is specified for the SORTSEQ system option, then
   PROC SQL honors the setting", and a CAUTION naming "the SORTSEQ=LINGUISTIC
   system option".

   With the exclusion refuted, nothing says the system option rejects the
   MODIFIER form, so D-018's asymmetry decides it: an undecided value stays on
   the gap arm, because a wrong rc 2 costs one spurious "file an opensas issue"
   while a wrong rc 1 tells a user their valid SAS is broken. opensas honours
   bare LINGUISTIC (rc_sortseq_linguistic_bare.sas) and implements none of the
   collating-options; silently ignoring them would change sort order without
   saying so (D-002).

   Twin rc_sortseq_xlate_table.sas holds the translation-table gap arm; the
   rc-1 typo arm is `sortseq=bogus`, pinned in main.zig's §5d test.
   expect-rc: 2 */
data a;
  x = 1;
run;
proc print data=a;
run;
options sortseq=linguistic(numeric_collation=on);

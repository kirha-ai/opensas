/* BUG-rcsplitmembership F4 — the gap arm of the SORTSEQ= split, re-derived in
   full. Base SAS 9.4 Procedures Guide, printed p.2410 (`=== pdf 2459 ===`):
   "Translation tables provided by SAS are: ASCII, DANISH, EBCDIC, FINNISH,
   ITALIAN, NORWEGIAN, POLISH, REVERSE, SPANISH, and SWEDISH." The first cut of
   the split carried five of the ten, so ITALIAN/POLISH/SPANISH/REVERSE were
   reported as typos at rc 1 — real SAS runs them, so they are opensas gaps and
   exit 2. ASCII is the tenth and is honoured (rc 0), not a gap: it is our own
   collation. Twin rc_sortseq_linguistic_sysopt.sas holds the rc-1 typo arm.
   expect-rc: 2 */
data a;
  x = 1;
run;
proc print data=a;
run;
options sortseq=italian;

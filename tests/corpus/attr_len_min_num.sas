/* BUG-attrboundssilent (4a, numeric arm) — same entry, printed p.217:
   "For numeric variables, 2 to 8 bytes or 3 to 8 bytes, depending on your
   operating environment." 0 and 1 are out of range on EVERY platform the doc
   lists, z/OS included, so a universal < 2 floor needs no platform decision.
   Both were accepted silently at rc 0 (descriptor fell back to Num 8).

   ONLY the 2-vs-3 boundary is genuinely platform-dependent (legal z/OS,
   illegal UNIX/Windows) and stays parked — accepted, pinned in-source only
   (parser.zig test), deliberately not a corpus golden so the manager can
   flip the park without reddening a fixture. The legal edges (3, 8) are
   pinned green by attr_bounds_doc.sas, which must not move.

   Parse-time failure → empty golden; the rc is the pin.
   expect-rc: 1 */
data t;
  length n 1;
run;

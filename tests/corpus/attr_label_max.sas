/* BUG-attrboundssilent (4b) — LABEL Statement, printed p.207 (marker
   "=== pdf 218 ===", footer "LABEL Statement 207"): "text-string specifies a
   label of up to 256 bytes." A 257-byte label was stored IN FULL at rc 0 with
   no diagnostic (measured on a clean build at 9f9958ea). rideAsLabel is the
   single choke point both label producers (LABEL statement, ATTRIB LABEL=)
   route through; the cap is enforced there so no sibling path stays silent.
   ERROR-vs-truncate is doc-silent — D-002 forbids the silent store either
   way, and an over-cap label is a malformed program -> rc 1 (D-009b(ii)).

   The legal edge (exactly 256 bytes) is pinned green by attr_bounds_doc.sas,
   which must not move. Parse-time failure -> empty golden; the rc is the pin.
   expect-rc: 1 */
data t;
  length v $3;
  v = 'abc';
  label v = 'XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX';
run;

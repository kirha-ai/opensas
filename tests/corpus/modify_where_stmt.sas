/* GAP-modifywherestmt — a WHERE STATEMENT in a MODIFY step: filter-then-match,
   implemented. Was refused at rc 2 (safe, but a gap); before the refusal it was
   silently wrong in OPPOSITE directions per shape (single-dataset IGNORED the
   statement; the BY shape flushed the filtered copy and DESTROYED hidden rows).

   The exact case — a WHERE excluding a master row whose BY key a transaction
   row matches — is GENUINELY DOC-SILENT (Table 23.3 has no subsetting row;
   _DSENMR does not distinguish physically-absent from WHERE-excluded), but
   every timing statement points one way and one names MODIFY explicitly:
     * Statements ref printed p.360: "SAS selects observations from each input
       data set before it combines them"
     * printed p.245: "uses dynamic WHERE processing to locate the matching
       observation"
   So FILTER-THEN-MATCH: the scan/match reads the filtered copy, the commit
   re-emits the UNFILTERED member (ModifyState.src_pos), and a hidden master
   row is never matched AND never destroyed.

   Riders pinned here: (1) p.360 requires WHERE variables in ALL the data
   sets, so the bare statement filters the TRANSACTION too (block 2);
   (2) WHEREUP= defaults to NOT re-evaluating written rows (Language Reference: Concepts p.215), so a
   row updated out of the filter is still written (block 4).
   expect-rc: 0 */

/* ---- 1: BY shape, WHERE on the BY var — the old DESTROY shape, flipped.
        k=1 is hidden from the match and from the transaction; it must come
        back EXACTLY as stored. k=2 is overlaid; k=3 is selected but unmatched. */
data m; do k = 1 to 3; v = k * 10; output; end; run;
data t; k = 2; v = 999; output; run;
data m;
  modify m t;
  by k;
  where k > 1;
run;
proc print data=m noobs; title "1 by + where: k=1 survives, k=2 -> 999"; run;

/* ---- 2: rider 1 (p.360) — the bare statement filters the TRANSACTION too.
        t k=1 fails k>1, so it never iterates: no _DSENMR, no p.600 ERROR
        (rc 0 is the assertion), and master k=1 stays untouched. */
data m2; do k = 1 to 2; v = k * 10; output; end; run;
data t2; k = 1; v = 111; output; k = 2; v = 222; output; run;
data m2;
  modify m2 t2;
  by k;
  where k > 1;
run;
proc print data=m2 noobs; title "2 transaction filtered too: k=1 -> 10 (not 111)"; run;

/* ---- 3: single-dataset shape — the statement was silently IGNORED before.
        Only the selected rows are read and updated. */
data s; do k = 1 to 4; v = k * 10; output; end; run;
data s;
  modify s;
  where k > 2;
  v = v + 1;
run;
proc print data=s noobs; title "3 single + where: 10 20 31 41"; run;

/* ---- 4: rider 2 (WHEREUP= default, Language Reference: Concepts p.215) — written rows are NOT
        re-evaluated: k=2..4 are selected, updated to NEGATIVE values that
        fail k>1, and still written (not removed, not re-filtered). */
data w; do k = 1 to 4; v = k; output; end; run;
data w;
  modify w;
  where k > 1;
  k = k - 10;
run;
proc print data=w noobs; title "4 no write-side re-eval: 1 -8 -7 -6"; run;

/* ---- 5: the where= OPTION twin on a BY master — same root fix. It discarded
        the positions and flushed the filtered copy: k=1 was GONE at rc 0. */
data o; do k = 1 to 4; v = k * 10; output; end; run;
data t5; k = 2; v = 999; output; run;
data o;
  modify o(where=(k>1)) t5;
  by k;
run;
proc print data=o noobs; title "5 where= option on BY master: k=1 survives"; run;

/* ---- 6: the doc-silent case, end to end. Master (k=1,x=5) fails where x>10;
        transaction (k=1,x=20) passes it (x rides BOTH inputs). Filter-then-
        match: the transaction is UNMATCHED (_DSENMR), the p.601 idiom OUTPUTs
        a NEW row, and the hidden master row is re-emitted untouched — the
        master ends with BOTH k=1 rows. */
data d; k = 1; x = 5; output; k = 2; x = 15; output; run;
data t6; k = 1; x = 20; output; k = 2; x = 25; output; run;
data d;
  modify d t6;
  by k;
  where x > 10;
  if _iorc_ = 1230015 then do; /* _DSENMR (modify_dsemtr.sas spells it out) */
    _error_ = 0;
    output;
  end;
run;
proc print data=d noobs; title "6 filter-then-match: (1,5) kept, (2,25), (1,20) added"; run;

/* BUG-modifymasteroptname — a MODIFY master's dataset OPTIONS must not be part
   of its NAME.

   The parser serializes `a(keep=y)` into ONE string so the AST stays a plain name
   list. `assertModifyMasterIsOutput` compared that whole blob against the DATA
   statement's name, so it could never match and every parenthesised master was
   rejected with a diagnostic that pointed at the wrong thing:
       ERROR: MODIFY updates a(keep = y ) in place, but the DATA statement names a
   Statements ref printed p.240 hangs `(data-set-options)` off MODIFY in all four
   Syntax Forms and its Notes say to put them there "and not in the DATA
   statement", so that was the ONLY documented spelling and it was unusable.

   ONE OWNER, NOT A SIXTH STRIPPER: five sites in exec.zig already split this
   encoding with their own inline `indexOfScalar(name, '(')`. They now all route
   through `splitSourceRef`, so the decoder cannot drift from its users — it IS
   them. The parser keeping name and options as separate FIELDS is the real fix and
   is recorded in-source as the upgrade: it would change four `[]const []const u8`
   lists in ast.zig and ~20 consumers, which is wider than this ticket.

   THE SPLIT ALONE WOULD HAVE BEEN WORSE THAN THE BUG. Unblocking the documented
   spelling made a ROW-SUBSETTING option destroy data: measured on a 3-observation
   master, `modify a(where=(x>15));` committed 2 rows and `modify a(obs=2);`
   committed 2 of 4, because the in-place rebuild re-emitted from the FILTERED copy.
   Those names were therefore refused at rc 2 for one tick.

   THAT REFUSAL IS NOW AN IMPLEMENTATION (BUG-modifywhereopt), and this fixture's
   rc moved 2 -> 0 as the deliberate consequence — the golden diff IS the flip, which
   is why block 4 was written as a pin of the refusal rather than of a message. The
   iteration reads the filtered copy while the commit indexes the UNFILTERED master
   through ModifyState.src_pos, so unselected observations are re-emitted untouched.
   Block 4 now pins the VALUES, and the row that the filter hides is the assertion
   that matters.
   expect-rc: 0 */

/* ---- 1: COLUMN-ONLY options on the master now WORK. Previously rejected;
        verified safe (no row set changes), so they are not in the gap arm. ---- */
data b; do y = 1 to 3; z = y * 5; output; end; run;
data b;
  modify b(keep=y z);
  y = y + 100;
run;
proc print data=b noobs; title "1 keep= on the master: 3 rows, y bumped"; run;

/* ---- 1b: the DESCRIPTOR FREEZE must still work when the master CARRIES options
        — the sibling caller (`modifyFrozenMaster`) needs the same split, and
        without it the freeze silently stopped protecting exactly this shape. A new
        variable must NOT reach the stored descriptor (GAP-ch23med-tick296 F3:
        MODIFY "cannot modify the descriptor portion … such as adding a variable",
        Statements ref printed p.240). Added because mutation testing found this
        uncovered: disabling that split left all 1859 cases GREEN, since with
        keep=y z the PDV and the master happened to agree. ---- */
data f; do y = 1 to 2; z = y; output; end; run;
data f;
  modify f(keep=y z);
  y = y + 1;
  brandnew = 99;   /* used in the step, never added to the frozen descriptor */
run;
proc contents data=f; title "1b freeze holds with options: 2 vars, no brandnew"; run;

/* ---- 2: a TWO-LEVEL master with options — the split must not eat the libref. */
data work.d; do q = 1 to 2; output; end; run;
data work.d;
  modify work.d(keep=q);
  q = q + 7;
run;
proc print data=work.d noobs; title "2 work.d(keep=q): 2 rows, 8 and 9"; run;

/* ---- 3: the D-014 control — a genuine MISMATCH must still be caught, and its
        message must now name the BARE name rather than the blob — is NOT in this
        fixture and deliberately so: it errors at rc 1, which would halt the run
        before block 4 and make this fixture's expect-rc ambiguous. It lives where
        it can assert the exact text instead of just the halt:
          * exec.zig test "BUG-modifymasteroptname: …" asserts BOTH messages via the
            captured reporter — `data b; modify a;` and `data b; modify a(keep=x);`
            producing the SAME rc-1 text naming `a`, not `a(keep = x )`.
          * tests/corpus/modify_outname_mismatch.sas keeps pinning the plain
            mismatch end-to-end at rc 1.
        No block below pretends to cover it. ---- */

/* ---- 4: a ROW-SUBSETTING option is now HONOURED, and the row it hides survives.
        x=10 fails the predicate, so it is never read and must come back EXACTLY as
        stored; 20 and 30 are read and updated. If the commit ever indexes the
        filtered copy again this row vanishes, which is what the old rc-2 refusal
        existed to prevent. ---- */
data a; do x = 10 to 30 by 10; output; end; run;
data a;
  modify a(where=(x>15));
  x = x + 1;
run;
proc print data=a noobs; title "4 where=: 10 untouched, 21, 31 — 3 rows"; run;

/* ---- 5: obs= and firstobs= are WINDOWS rather than predicates, and they compose.
        firstobs=2 obs=3 reads rows 2..3 of 4; rows 1 and 4 are outside the window
        and must be re-emitted untouched. This is the strongest single check that
        the position mapping threads across BOTH stages. ---- */
data w; do k = 1 to 4; v = k * 10; output; end; run;
data w;
  modify w(firstobs=2 obs=3);
  v = v + 1;
run;
proc print data=w noobs; title "5 firstobs=2 obs=3: 10 21 31 40"; run;

/* ---- 6: the tick440 rebuild must still hold INSIDE a filtered MODIFY. `stop` on
        the second selected row leaves the first one updated and every other row —
        selected-but-unreached AND never-selected — exactly as stored. ---- */
data sp; do k = 1 to 4; v = k * 10; output; end; run;
data sp;
  modify sp(where=(k>1));
  if k = 3 then stop;
  v = v + 1;
run;
proc print data=sp noobs; title "6 where + stop: 10 21 30 40"; run;

/* ---- 7: REMOVE under a filter deletes only a SELECTED row; the rows the filter
        hid are not candidates and survive. ---- */
data rm; do k = 1 to 4; v = k * 10; output; end; run;
data rm;
  modify rm(where=(k>2));
  if k = 3 then remove;
run;
proc print data=rm noobs; title "7 where + remove k=3: k=1,2,4 remain"; run;

/* GAP-sqleqtjoinlen — DECLINED AS DOC-UNDECIDABLE, current behaviour pinned.

   This fixture does NOT assert conformance. It records an open question and
   guards the three positions against silent drift until an oracle settles it.

   SQL Procedure User's Guide, printed p.405, immediately after the sentence that
   assigns the trailing-blank rules to the two surfaces:

     "TIP If EQT is used in JOIN criteria, the length of values is always used. A
      sub-setting WHERE clause uses the shortest length of the column or
      expression."

   opensas applies the trimmed shortest-length rule in ALL THREE positions below,
   so the WHERE half is doc-CONFIRMED and only the JOIN half is in question. It is
   not implementable from this text, for two independent reasons.

   (1) "the length of values is always used" has two coherent readings and the
       volume never disambiguates them:
         (A) no truncation at all in join criteria — the whole values are
             compared, so EQT degenerates to plain `=` there. The word "always",
             set against "the shortest length", leans this way, and it matches the
             engineering reason a TIP would exist (an equijoin key cannot carry a
             truncated comparison).
         (B) the truncation length is taken from the VALUES (padded to their
             storage width) rather than from the column/expression — which for two
             column operands is the SAME number, making the TIP nearly vacuous.
       (A) DROPS rows that (B) keeps: case 1 below would lose the PQR/PQ row.
       Silently dropping observations is the failure class this project treats as
       worst, so it is not a coin to flip.

   (2) Even granting (A), "JOIN criteria" cannot be told apart from "a sub-setting
       WHERE clause" for PROC SQL's most common join syntax — and the volume's own
       vocabulary is what blocks it:
         printed p.341: "Specify the join criteria. The WHERE clause specifies the
           columns that join the tables." (a comma-join's WHERE *is* the join
           criteria)
         printed p.317: "Specify the join criterion and subset the query. The
           WHERE clause specifies that the tables are joined on the ID number from
           each table. WHERE also further subsets the query with the IN
           condition." (ONE WHERE clause is BOTH categories at once)
       The TIP gives those two categories OPPOSITE rules, so a single WHERE clause
       would need both. Nothing in any of the nine volumes says the rule is
       applied per-predicate by whether a predicate relates two tables. The TIP
       occurs exactly ONCE across all of them and has no worked example (the only
       EQT example, p.56, a WHERE against a trailing-blank literal, does not
       discriminate: trimmed and untrimmed both return the same rows).

   TO SETTLE IT an oracle run of real SAS 9.4 needs three numbers: cases 1, 2 and
   3 below. If case 1 returns one row and case 2 two, reading (A) holds and
   applies to ON only; if both return one row, (A) applies to a comma-join WHERE
   too; if all match what is pinned here, reading (B) holds and we are already
   conformant. Case 5 is the `=` control that (A) would make case 1 identical to. */

data inv; length tag $3; tag='PQR'; output; tag='ZW'; output; run;
data ord; length tag $4; tag='PQ';  output; tag='ZW'; output; run;

proc sql;
  title '1. explicit ON — "JOIN criteria" beyond doubt';
  select inv.tag as itag, ord.tag as otag from inv join ord on inv.tag eqt ord.tag;
  title '2. comma-join WHERE — the join criteria per p.341, a WHERE per the TIP';
  select inv.tag as itag, ord.tag as otag from inv, ord where inv.tag eqt ord.tag;
  title '3. sub-setting WHERE vs a literal — the doc-CONFIRMED half';
  select tag from inv where tag eqt 'PQ';
  title '4. sub-setting WHERE, column vs column, one table';
  select tag from inv where tag eqt tag;
  title '5. CONTROL: plain = , no truncation — what reading (A) would make 1';
  select inv.tag as itag, ord.tag as otag from inv join ord on inv.tag = ord.tag;
quit;
title;

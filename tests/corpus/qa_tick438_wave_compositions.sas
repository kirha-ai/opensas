/* QA tick438 cross-landing sweep — four COMPOSITIONS of this wave's landings
   that each landing's own fixtures do not cover. Every one is correct today;
   they are pinned because nothing else pins them and each crosses two changes.

   C1 obs= x FLOWOVER SPILL. Two landings in one statement: a FLOWOVER list-input
   spill that runs out of records now ends the step instead of writing a partial
   observation, and firstobs=/obs= on raw reads changed in the same wave. Before,
   this wrote `1 2 .` — a fabricated observation with a missing z. No fixture
   combines obs= with flowover (checked). Verified base-vs-head: only the partial
   row disappeared, the capped row is unchanged.

   C2 @@ x END-OF-DATA. `input x y @@;` over an ODD number of values is the same
   spill through a different door — @@ holds the record across iterations, and it
   is one of the "five producers" of a record advance the wave touched. The
   trailing half-observation `2 3 .` is gone. No fixture combines @@ with the
   flowover/EOF rules (checked).

   C3 ':' PUT MODIFIER x FLOWOVER. The `:` modified-list-output landing and the
   FLOWOVER landing meet in one step: the complete observation must still print
   through `:`, and the incomplete one must not reach PUT at all. This pins that
   the EOF stop happens before PUT rather than PUT formatting a partial row.

   C4 ROUNDE two-argument FUZZ. `rounde(0.035, 0.01)` is 0.04: 3.5 hundredths
   ties to the EVEN neighbour, 4. Without the fuzz this wave added it came out
   0.03, because 0.035 is 0.0349999... in binary and fell to the low side. This
   was the ONLY value to move across a 24-value sweep of halves and hundredths,
   which is the right blast radius for a fuzz — and existing coverage
   (cov_rounding, expr_op_semantics) pins only single-argument exact halves
   (rounde(2.5), rounde(3.5)), never a two-argument case. So the one observable
   effect of the change had no pin.
   expect-rc: 0 */

/* C1 — obs= caps the read; the FLOWOVER spill must not fabricate a row */
data c1;
  infile datalines flowover obs=1;
  input x y z;
  datalines;
1 2
3 4
;
run;
title "C1 obs=1 + flowover spill: no row at all, not 1 2 .";
proc print data=c1; run;

/* C2 — @@ over an odd value count drops the trailing half-observation */
data c2;
  infile datalines;
  input x y @@;
  datalines;
1 2 3
;
run;
title "C2 @@ odd count: one complete row only, no 2 3 .";
proc print data=c2; run;

/* C3 — the complete row prints through ':'; the incomplete one never reaches PUT */
data _null_;
  infile datalines flowover;
  input a b;
  put a :best8. b :best8.;
  datalines;
1 2
3
;
run;

/* C4 — two-argument ROUNDE fuzz, ties-to-even on the hundredth */
data _null_;
  f1 = rounde(0.035, 0.01);   /* 0.04 — 3.5 ties to even 4 */
  f2 = rounde(0.025, 0.01);   /* 0.02 — 2.5 ties to even 2 */
  f3 = rounde(2.675, 0.01);   /* 2.68 */
  put "rounde2arg " f1= f2= f3=;
run;

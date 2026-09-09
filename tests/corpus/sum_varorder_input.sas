/* BUG-sumvarorderinput: a sum statement FOLLOWING an INPUT does not hoist its
   accumulator ahead of the INPUT's variables. Verified already conformant at
   8805ad49 (which moved the auto `retain v 0;` from a step-TOP hoist to right
   after the sum statement); this fixture exists because NOTHING pinned it —
   the raw-INPUT half of the ordering rule had no corpus coverage, so it could
   regress silently.

   REPORT 1 pins the Language Reference: Concepts Chapter 20 rule ("Processing
   a DATA Step: A Walk-through", printed p.481, page marker verified). The
   source order there is INPUT first, sum statement second — which is the
   deciding detail, since the whole question is first-mention ORDER. Its
   Figure 20.6 / Figure 20.8 print the result with the accumulator as the LAST
   column, after every INPUT variable, and the drop= variable gone. The same
   shape here: a six-row relay sheet, Club dropped, RunTotal last, running
   totals 21, 44, 65, 91, 111, 138.
   Report 2 pins the same via PROC CONTENTS, whose `#` column IS the position
   attribute Language Reference: Concepts printed p.47 defines ("position in observation is determined
   by the order in which the variables are defined in the DATA step").
   Report 3 is the minimal repro shape from the ticket.

   REPORT 4 IS THE CONVERSE AND IT IS *NOT* DOC-SETTLED — pinned to make the
   asymmetry visible, NOT to bless it. With the sum statement BEFORE the INPUT,
   opensas still emits `Runner Pts Cnt`; p.47's textual rule argues for
   `Cnt Runner Pts`, the way `retain t 0; set a;` orders t first. The 9.4
   volumes show no example of this shape, and INPUT variables are pre-declared
   at a fixed point in the prologue rather than at their statement node, so
   changing it is a separate ticket with its own golden movement. If that
   ticket lands, THIS report is the one that moves. */
data race_points (drop=Club);
   input Club $ Runner $ Leg1 Leg2 Leg3;
   RunTotal + (Leg1 + Leg2 + Leg3);
   datalines;
Otters Mia    5  7  9
Herons Noah   8  6  9
Otters Ivy    7  8  6
Herons Omar   9  9  8
Herons Lena   6  7  7
Otters Tobias 8  9 10
;
run;
proc print data=race_points; run;
proc contents data=race_points; run;
data t3;
  input Runner $ Pts;
  RunTotal + Pts;
  datalines;
Mia 5
Noah 8
;
run;
proc print data=t3; run;
data t4;
  Cnt + 1;
  input Runner $ Pts;
  datalines;
Mia 5
;
run;
proc print data=t4; run;

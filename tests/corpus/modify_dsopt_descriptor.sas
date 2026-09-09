/* BUG-modifydsoptdescriptor — a MODIFY master's descriptor is frozen against
   the DATASET-OPTION spelling too, not only the statement spelling.

   GAP-ch23med-tick296 F3 (7a0cf735) froze `modify d; drop y;` at exec.zig's
   schema choke point. The dataset-option spelling goes through a DIFFERENT
   door: main.zig applies `data d(drop=y)` options AFTER the step, straight onto
   the committed data set, where the freeze never saw them. So until this fix
   opensas was INTERNALLY INCONSISTENT — `modify d; drop y;` preserved the
   column while `data d(drop=y); modify d;` deleted it and every value in it,
   and the destructive half was the spelling a user is more likely to write.

   WHAT IS PINNED IS THE DESTRUCTION, NOT A DIAGNOSTIC. There is no error
   message to assert: SAS accepts these silently (see below), so the only
   evidence is the DATA. Revert the fix and this golden LOSES column y and both
   its values (D1/D2) or shows x renamed to xx (D3) — a row of real numbers
   disappearing from the expected output.

   DOC POSITION, STATED HONESTLY. Cited: SAS 9.4 DATA Step Statements Reference
   printed p.253 (`=== pdf 264 ===`, offset +11), MODIFY Example 3 — "MODIFY
   does not add NWSTOCK to the INVTY.STOCK data set BECAUSE THAT WOULD MODIFY
   THE DATA SET DESCRIPTOR. Thus, it is not necessary to put NWSTOCK in a DROP
   statement." The reason given is about the descriptor, not about a syntax, and
   the same sentence is why this is silent rather than an ERROR. NOT cited: no
   passage in the volumes names DATASET OPTIONS on a MODIFY master, so applying
   the rule to this spelling is D-018's internal-consistency argument — two
   spellings of one operation must not disagree, and when they do, the arm that
   silently destroys a column loses.

   D4 was added later by BUG-modifydsoptwhere and has its own citations at the
   block: WHERE= on this same spelling was PERMANENTLY DELETING rows from the
   stored file, which is the same class of destruction one option further out.

   Blocks C1/C2/C4 are the controls that keep the fix from over-reaching: the
   options must still work everywhere except on the master itself, and an
   unknown option must still fail loud.
   expect-rc: 1 */

/* D1 — drop= must NOT delete y from the master */
title "D1 dsopt drop=y on the master: k x y all present, y = 100/200";
data d1; length k 8 x 8 y 8; k=1;x=10;y=100;output; k=2;x=20;y=200;output; run;
data d1(drop=y); modify d1; x = x + 1; run;
proc print data=d1; run;

/* D2 — keep= is the same edit stated positively */
title "D2 dsopt keep=k x on the master: y survives anyway";
data d2; length k 8 x 8 y 8; k=1;x=10;y=100;output; k=2;x=20;y=200;output; run;
data d2(keep=k x); modify d2; x = x + 1; run;
proc print data=d2; run;

/* D3 — rename= is a different symptom with the same root: an in-place update
   silently coming back under another name */
title "D3 dsopt rename=(x=xx) on the master: the column stays x";
data d3; length k 8 x 8 y 8; k=1;x=10;y=100;output; k=2;x=20;y=200;output; run;
data d3(rename=(x=xx)); modify d3; x = x + 1; run;
proc print data=d3; run;

/* C1 — the ordinary (non-MODIFY) dataset-option path must be untouched */
title "C1 control: drop= on a plain SET step still drops y";
data c1; length k 8 x 8 y 8; k=1;x=10;y=100;output; run;
data c1b(drop=y); set c1; run;
proc print data=c1b; run;

/* C2 — per-OUTPUT, not per-step: a NON-master output of the same MODIFY step is
   a brand-new data set and still takes the full PDV schema, so its drop= must
   still apply. This is exec.zig's own p.260 Example 8 rule, held on this path. */
title "C2 control: a non-master output of a MODIFY step still honours drop=";
data c2; length k 8 x 8 y 8; k=1;x=10;y=99;output; run;
data c2 c2other(drop=y); modify c2; x = x + 1; run;
proc print data=c2; run;
proc print data=c2other; run;

/* D4 — WHERE=, added by BUG-modifydsoptwhere. THIS BLOCK USED TO BE CONTROL C3
   AND PINNED THE OPPOSITE ANSWER ON PURPOSE: the descriptor fix deliberately
   left WHERE= alone (it is row loss, not a descriptor edit, and that ticket had
   no citation for it), and C3 pinned the then-current behaviour so the next
   owner could watch it move. It has now moved, which is the whole reason it was
   written that way — the golden edit below is that pin being collected, not a
   result being re-blessed.

   What it was doing: PERMANENTLY DELETING every non-matching observation from
   the STORED data set — k=1 was gone from the .sas7bdat, confirmed through four
   independent read paths and then from a SEPARATE PROCESS re-reading the file.
   Silent, permanent data loss.

   Why that is wrong: MODIFY has no output to filter. Statements Reference
   printed p.240 (`=== pdf 251 ===`, offset +11) — "Replaces, deletes, and
   appends observations in an existing SAS data set IN PLACE but does not create
   an additional copy" — and all four Syntax Forms hang `<(data-set-options)>`
   off the MODIFY statement, while the DATA statement carries only the bare
   Restriction "This data set must also appear in the DATA statement". The Notes
   say the master's options go "in the MODIFY statement, AND NOT IN THE DATA
   STATEMENT". Corroborating that WHERE= is a normal MODIFY-side option: p.244's
   POINT= Restrictions bar it there by name, which is only meaningful because it
   is available otherwise.

   Silent rather than an ERROR for internal consistency with D1-D3 above, whose
   silence p.253 does license. All three rows must survive, all three updated. */
title "D4 dsopt where= on the master: all 3 rows survive, all 3 updated";
data c3; length k 8 x 8; k=1;x=10;output; k=2;x=20;output; k=3;x=30;output; run;
data c3(where=(x>15)); modify c3; x = x + 1; run;
proc print data=c3; run;

/* E1-E3 — THE SECOND DOOR, found by a mutation that reddened NOTHING (D-021).
   Disabling the strip on the EXTRAS loop (`data a b(…);`'s non-primary outputs)
   left the whole suite green, which meant either dead code or a coverage hole.
   It is a hole: the branch fires whenever an extra output name resolves to the
   SAME member as the master, and all three shapes below reach it. E3 is the one
   that earns its keep — `e3` and `work.e3` are the same member, so it is the
   proof that matching the master BY POINTER through `lib.find` (rather than by
   comparing name strings) is what makes this correct. */
title "E1 master named twice, drop= on the second mention: y survives";
data e1; length k 8 x 8 y 8; k=1;x=10;y=100;output; run;
data e1 e1(drop=y); modify e1; x = x + 1; run;
proc print data=e1; run;

title "E2 same door, where=: both rows survive";
data e2; length k 8 x 8; k=1;x=10;output; k=2;x=20;output; run;
data e2 e2(where=(x>15)); modify e2; x = x + 1; run;
proc print data=e2; run;

title "E3 one-level vs two-level name for the same member: y still survives";
data e3; length k 8 x 8 y 8; k=1;x=10;y=100;output; run;
data e3 work.e3(drop=y); modify e3; x = x + 1; run;
proc print data=e3; run;

/* C4 — the stripped option list is still HANDED TO the validator rather than
   skipped, so an unknown option on a MODIFY master keeps failing loud (D-002).
   Skipping the call outright would have traded one silent bug for another.
   Kept last: it is the one error in this fixture (BUG-errhalt "one error, last").
   This block is why the pin at the top of the file is 1 rather than 0. (Worded
   without quoting the marker token: fixture_rc treats a SECOND occurrence of it
   as error.AmbiguousMarker, so prose that quotes it breaks the fixture.) */
title "C4 control: an unknown option on a MODIFY master still fails LOUD";
data c4; length k 8 x 8; k=1;x=10;output; run;
data c4(bogusopt=1); modify c4; x = x + 1; run;

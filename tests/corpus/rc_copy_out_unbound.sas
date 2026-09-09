/* DEC-abortrcvsD009 (2a57cc33, main.zig 622) — `out=` naming a libref that was
   never assigned is a USER error (real SAS: "Libref NOLIB is not assigned"),
   D-009 rc 1. This is the row that needed the MIRROR of 321b444e's reductio:
   "we might have failed to bind a libref we should have" cannot demote it to a
   gap, or every user error could be re-described as a suspected opensas defect
   and rc 1 would be unreachable. That argument is now enforced, not just
   written down.
   expect-rc: 1 */
data a;
  x = 1;
run;
proc print data=a;
run;
proc copy in=work out=nolib;
run;

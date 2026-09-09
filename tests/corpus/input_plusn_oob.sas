/* BUG-inputplusncol: the relative column pointer `+n` positioned PAST the end of a
   short input line must NOT crash (was rc=134 SIGABRT). The `+n` cursor is clamped
   to line.len (mirror of the @n / @s-e clamps).

   GAP-inputeofdegrade REVISED WHAT HAPPENS NEXT, and the "no crash" subject is
   now demonstrated MORE strongly rather than less. A pointer past the end of the
   record is not an end-of-DATA condition: Statements ref printed p.177 says "When
   you use @ or + pointer controls with a value that moves the pointer to or past
   the end of the current record and the next value is to be read from the current
   column, SAS goes to column 1 of the next record to read it", with the
   "went to a new line" NOTE. So the read FLOWS — it only stops if there is no
   next record, per printed p.178 ("If a DATA step tries to read another record
   after it reaches an end-of-file, then execution stops").
   oob1/oob2 have no following record, so the step ends and NO observation is
   written — they used to emit one with the variable missing, which is MISSOVER's
   documented behaviour (printed p.133) applied under FLOWOVER (printed p.132).
   flow1/flow2 are NEW and carry a following record, so they still prove the
   clamp does not crash AND pin the documented flowed value.
   oob1: `+99 a` on "12" alone                  → step ends, NO obs (no crash).
   oob2: `a +99 b` on "12 34" alone             → step ends, NO obs (no crash).
   flow1: `+99 a` on "12" / "77"                → a=77 (flowed to the next record).
   flow2: `a +99 b` on "12 34" / "88"           → a=12, b=88 (flowed).
   ctrl: `a +2 b` on "1  22" (in range)          → a=1, b=22 (normal skip, unchanged). */
data oob1;
  input +99 a;
  datalines;
12
;
run;
data oob2;
  input a +99 b;
  datalines;
12 34
;
run;
data flow1;
  input +99 a;
  datalines;
12
77
;
run;
data flow2;
  input a +99 b;
  datalines;
12 34
88
;
run;
data ctrl;
  input a +2 b;
  datalines;
1  22
;
run;
proc print data=oob1 noobs; run;
proc print data=oob2 noobs; run;
proc print data=flow1 noobs; run;
proc print data=flow2 noobs; run;
proc print data=ctrl noobs; run;

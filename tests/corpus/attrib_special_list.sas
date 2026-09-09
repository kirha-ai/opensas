/* BUG-speciallistphantom (GH#79 part 1) — _ALL_/_NUMERIC_/_CHARACTER_ are SAS
   variable name LISTS, never variables of their own: ATTRIB's "TIP List the
   variables in any form that SAS allows" (Statements Ref printed p.34)
   delegates to the canonical enumeration at printed p.24 — "_NUMERIC_
   specifies all numeric variables. _CHARACTER_ specifies all character
   variables. _ALL_ specifies all variables." ATTRIB, LENGTH, FORMAT and
   INFORMAT each seeded the keyword as a real variable instead: a phantom
   `_all_ Num 8` (etc.) column appeared in the output at rc 0 with zero
   diagnostics, and the requested attribute never reached the real variables.
   Every case below must show EXACTLY the real variables (no column named
   after a keyword) WITH the attribute applied — PROC CONTENTS pins both. */

/* A — ATTRIB over _NUMERIC_: BEST8. reaches the numeric vars only; no
   `_numeric_` column. */
data a;
  c = "s"; x = 1; y = 2;
  attrib _numeric_ format=best8.;
  stop;
run;
proc contents data=a; run;

/* B — the LENGTH-statement variant: `length _all_ 8;` seeds nothing — the vars
   the list names are established (first length wins) or not yet born, so the
   columns are exactly a/n. */
data b;
  a = "x"; n = 1;
  length _all_ 8;
  stop;
run;
proc contents data=b; run;

/* C — the FORMAT/INFORMAT statement variants over _ALL_ (an all-numeric PDV
   keeps a numeric format's attach type-legal): both attach to every var, and
   there is no `_all_` column. */
data c;
  p = 1; q = 2;
  format _all_ 8.2;
  informat _all_ 8.2;
  stop;
run;
proc contents data=c; run;

/* D — ATTRIB over _CHARACTER_ with a character format: reaches the char var
   only. This is the SAS-idiomatic typed cleanup form — `format _all_ best8.;`
   on a PDV holding a CHARACTER variable is the illegal attach SAS errors
   ("The numeric format best8. cannot be used with character variable c.",
   whichever way the variable was named), which attrib_special_conflict pins. */
data d;
  s = "ab"; n = 1;
  attrib _character_ format=$8.;
  stop;
run;
proc contents data=d; run;

/* E — the GH#79 reporter's actual intent: clearing the format off EVERY
   variable in a DATA step. The documented removal is the bare FORMAT
   statement (printed p.112) — and over _ALL_ it now clears them all, instead
   of minting a phantom while the old format stayed attached. */
data src;
  x = 21929; d = 1;
  format x date9. d yymmdd10.;
  output;
run;
data e;
  set src;
  format _all_;
run;
proc print data=e noobs; run;

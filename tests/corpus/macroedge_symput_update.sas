/* BUG-symputnoupdate — CALL SYMPUT UPDATES an existing macro variable; it only
   CREATES one when the name exists nowhere. SAS 9.4 Macro Language: Reference,
   Fifth Edition, printed p.301 ("CALL SYMPUT Routine"):

     "If macro-variable exists in any enclosing scope, macro-variable is
      updated. If macro-variable does not exist, SYMPUT creates it."

   The p.77 rule-1 placement pinned by macroedge_symput_scopelocal answers only
   the SECOND sentence — where a NEW variable is created. Running it
   unconditionally made every CALL SYMPUT inside a parameterized macro shadow the
   variable it was meant to write, which silently defeated the doc's own
   prescribed remedy for the scope trap (printed p.152: "you must use a %GLOBAL
   statement to declare the macro variable MACVAR").

   Asserted through DATA-step `put` (stdout): `%put` writes to STDERR, which the
   corpus does not diff, so a %put-only golden passes vacuously. corpus-macroedge. */

/* p.152's remedy, verbatim in shape: %GLOBAL inside a PARAMETERIZED macro (whose
   local table is therefore non-empty), then CALL SYMPUT. The global must be
   UPDATED, not shadowed — this printed `[]` before the fix. */
%macro remedy(p=);
   %global gv;
   data _null_;
      call symput('gv', 'a token');
   run;
%mend remedy;
%remedy(p=Z)
data _null_;
   put "remedy-open=[&gv]";
run;

/* A pre-existing GLOBAL created by %LET, updated from inside a parameterized
   macro. Kept OLD before the fix. */
%let gv2 = OLD;
%macro upd(p=);
   data _null_;
      call symput('gv2', 'NEW');
   run;
   data _null_;
      put "upd-inside=[&gv2]";
   run;
%mend upd;
%upd(p=Z)
data _null_;
   put "upd-open=[&gv2]";
run;

/* "the most local symbol table in which it exists": OUTER owns OV via %LOCAL, so
   INNER's symput must write OUTER's copy even though INNER has a non-empty frame
   of its own. Before the fix INNER created a private shadow that died at %MEND
   and OUTER still saw `start`. */
%macro inner2(q);
   data _null_;
      call symput('ov', 'from-inner');
   run;
%mend inner2;
%macro outer2;
   %local ov;
   %let ov = start;
   %inner2(7)
   data _null_;
      put "outer2-inside=[&ov]";
   run;
%mend outer2;
%outer2
data _null_;
   put "outer2-open=[&ov]";
run;

/* THE GUARD against over-correcting: a name that exists NOWHERE is still CREATED
   by rule 1, i.e. LOCAL to a parameterized macro and gone in open code. This is
   the ENV1 half of macroedge_symput_scopelocal and must not drift. */
%macro fresh(param1);
   data _null_;
      call symput('nv', 'a token');
   run;
   data _null_;
      put "fresh-inside=[&nv]";
   run;
%mend fresh;
%fresh(10)
data _null_;
   put "fresh-open=[&nv]";
run;

/* SYMPUTX takes the same p.301 route (printed p.307 defers to it for the
   create/update decision), so the update must work there too. */
%let sx = OLD;
%macro updx(p=);
   data _null_;
      call symputx('sx', '  NEWX  ');
   run;
%mend updx;
%updx(p=1)
data _null_;
   put "updx-open=[&sx]";
run;

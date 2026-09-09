/* BUG-symputxsymtab — CALL SYMPUTX's THIRD argument, `symbol-table`. SAS 9.4
   Macro Language: Reference, Fifth Edition, printed p.307 ("CALL SYMPUTX
   Routine"):

     G — "stored in the global symbol table, even if a local symbol table exists"
     L — "the most local symbol table that exists. ... If a local symbol table
          does not exist ... the global symbol table"
     F — the DEFAULT: "if the macro variable exists in any symbol table, CALL
          SYMPUTX uses the version in the most local symbol table in which it
          exists. If the macro variable does not exist, CALL SYMPUTX stores the
          variable in the most local symbol table that it finds."

   It was PARSED AND DISCARDED with no diagnostic — a silent no-op, which D-002
   forbids outright. An argument outside G/L/F is a LOUD error; that arm is
   asserted on the captured reporter in src/exec.zig, not here.

   Values are asserted through DATA-step `put` (stdout): `%put` writes to STDERR,
   which the corpus does not diff, so a %put-only golden passes vacuously.
   corpus-macroedge. */

/* Pins the pp.307-308 shape: a parameterized macro (so a local table exists)
   writes one pre-existing GLOBAL with 'L' and one with the default, and open
   code then reads both back. The expected values, in order:
       local slots outer blanks are stripped away
       slots=!5!
       y=!987.25!
   Both defects show up in this one program: `slots` needs 'L' (it exists
   globally, so without the third argument the default F would UPDATE the global
   and open code would print the new text), and `y` needs the p.301 update rule
   (before BUG-symputnoupdate it got a dead local shadow and open code kept 3). */
%let y=3;
%let slots=5;
%macro probe(val);
data _null_;
 call symputx('slots', ' outer blanks are stripped away ', 'L');
 call symputx('  y   ', 987.25);
run;
%put local slots &slots;
%mend probe;
%probe(100)
%put slots=!&slots!;
%put y=!&y!;
/* the same three lines on stdout, where the corpus can actually diff them */
%macro probe2(val);
data _null_;
 call symputx('slots2', ' outer blanks are stripped away ', 'L');
 call symputx('  y2   ', 987.25);
run;
data _null_;
   put "local slots2 &slots2";
run;
%mend probe2;
%let y2=3;
%let slots2=5;
%probe2(100)
data _null_;
   put "slots2=!&slots2!";
   put "y2=!&y2!";
run;

/* G — the global table "EVEN IF a local symbol table exists". The macro is
   parameterized, so rule 1 would have made this local; 'G' overrides that and
   open code sees it. This is the reporter's repro. */
%macro gtab(p);
   data _null_;
      call symputx('gv', 'val', 'G');
   run;
%mend gtab;
%gtab(1)
data _null_;
   put "gtab-open=[&gv]";
run;

/* G while a LIVE %LOCAL of the same name is shadowing it: the local keeps its
   own value for the rest of the macro, and the global write surfaces once the
   local dies. */
%macro gshadow;
   %local sh;
   %let sh = LOCALVAL;
   data _null_;
      call symputx('sh', 'GLOBALVAL', 'G');
   run;
   data _null_;
      put "gshadow-inside=[&sh]";
   run;
%mend gshadow;
%gshadow
data _null_;
   put "gshadow-open=[&sh]";
run;

/* L — "the most local symbol table that exists", so it dies with the macro even
   though a GLOBAL of the same name already existed (that is the whole point of
   the `slots` block above). */
%let lv = KEEPME;
%macro ltab(p);
   data _null_;
      call symputx('lv', 'only-local', 'L');
   run;
   data _null_;
      put "ltab-inside=[&lv]";
   run;
%mend ltab;
%ltab(1)
data _null_;
   put "ltab-open=[&lv]";
run;

/* L with NO local symbol table at all (open code) → the global table. */
data _null_;
   call symputx('lopen', 'x', 'L');
run;
data _null_;
   put "lopen=[&lopen]";
run;

/* F, spelled out, is the default: same result as omitting the argument. Both
   names pre-exist globally, so both are UPDATED in place (p.307's F clause). */
%let f1 = OLD;
%let f2 = OLD;
%macro ftab(p);
   data _null_;
      call symputx('f1', 'NEW', 'F');
      call symputx('f2', 'NEW');
   run;
%mend ftab;
%ftab(1)
data _null_;
   put "ftab-open=[&f1][&f2]";
run;

/* The value is an EXPRESSION, not just a literal — a variable holding 'G' picks
   the global table exactly the same way, and case does not matter. */
%macro gvar(p);
   data _null_;
      tab = 'g';
      call symputx('gv2', 'from-var', tab);
   run;
%mend gvar;
%gvar(1)
data _null_;
   put "gvar-open=[&gv2]";
run;

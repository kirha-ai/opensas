/* BUG-symputscope — WHERE CALL SYMPUT creates its variable. SAS 9.4 Macro
   Language: Reference, Fifth Edition, printed p.77 ("Special Cases of Scope with
   the CALL SYMPUT Routine"), rule 1: the variable is created "in the current
   symbol table available while the DATA step is executing, provided that symbol
   table is not empty. If it is empty (contains no local macro variables), usually
   CALL SYMPUT creates the variable in the closest nonempty symbol table."

   So a PARAMETERIZED macro (non-empty local table) and a PARAMETER-LESS one
   (empty local table) must behave DIFFERENTLY — that clause is the whole
   subtlety, and both halves are pinned below so neither drifts into the other.
   These are the doc's own ENV1/ENV2/ENV3/ENV4 examples (printed pp.78-84).

   Everything is asserted through a DATA-step `put` (stdout): `%put` writes to
   STDERR, which the corpus does not diff, so a %put-only golden passes vacuously.
   corpus-macroedge. */

/* ENV1 (printed p.78) — parameterized macro, COMPLETE data step (`run;` inside
   the macro). Local table holds PARAM1, so it is not empty => MYVAR1 is LOCAL to
   ENV1 and is gone in open code. SAS logs "Apparent symbolic reference MYVAR1
   not resolved" and the reference stays literal. */
%macro env1(param1);
   data _null_;
      x = 'a token';
      call symput('myvar1', x);
   run;
   /* still visible INSIDE the body — this is D-004/BUG-macrointerleave and must
      not be lost while making the variable local (the study meter 0/27 -> 26/27). */
   data _null_;
      put "env1-inside=[&myvar1] param=[&param1]";
   run;
%mend env1;
%env1(10)
data _null_;
   put "env1-open=[&myvar1]";
run;

/* ENV2 (printed p.81) — parameterized macro, INCOMPLETE data step: the `run;` is
   in open code, so the step completes in the GLOBAL scope. MYVAR2 is global and
   the value survives the macro. */
%macro env2(param2);
   data _null_;
      x = 'a token';
      call symput('myvar2', x);
%mend env2;
%env2(20)
run;
data _null_;
   put "env2-open=[&myvar2]";
run;

/* ENV3 (printed p.83) — NO parameters, so the local table is EMPTY: the complete
   data step still runs inside the macro, but the variable goes to the closest
   nonempty table, the global one. This is the contrast with ENV1: same shape,
   same `run;` placement, opposite outcome, decided only by emptiness. */
%macro env3;
   data _null_;
      x = 'a token';
      call symput('myvar3', x);
   run;
   data _null_;
      put "env3-inside=[&myvar3]";
   run;
%mend env3;
%env3
data _null_;
   put "env3-open=[&myvar3]";
run;

/* A %LOCAL alone also makes the table non-empty — "contains no local macro
   variables" is about the table, not about parameters specifically. */
%macro env3b;
   %local dummy;
   data _null_;
      call symput('myvar3b', 'a token');
   run;
%mend env3b;
%env3b
data _null_;
   put "env3b-open=[&myvar3b]";
run;

/* "the CLOSEST nonempty symbol table" — INNER's own table is empty, so the
   variable lands in OUTER's, not in the global one: visible to OUTER after
   INNER returns, dead once OUTER returns. */
%macro inner;
   data _null_;
      call symput('nested', 'a token');
   run;
%mend inner;
%macro outer(p);
   %inner
   data _null_;
      put "nested-in-outer=[&nested]";
   run;
%mend outer;
%outer(9)
data _null_;
   put "nested-open=[&nested]";
run;

/* ENV4 (printed p.83) — the SYSPBUFF exception: /PARMBUFF creates SYSPBUFF at
   invocation, so the local table is not empty even though ENV4 takes no
   parameters, and MYVAR4 is local. Falls out of rule 1 here because SYSPBUFF is
   itself declared local. */
%macro env4 / parmbuff;
   data _null_;
      call symput('myvar4', 'a token');
   run;
   data _null_;
      put "env4-inside=[&myvar4]";
   run;
%mend env4;
%env4
data _null_;
   put "env4-open=[&myvar4]";
run;

/* Control: open-code CALL SYMPUT is unaffected — no local table at all. */
data _null_;
   call symput('plain', 'a token');
run;
data _null_;
   put "plain-open=[&plain]";
run;

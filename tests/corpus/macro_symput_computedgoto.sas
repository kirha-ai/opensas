/* GAP-macrooracle-tick284 (F9) — CALL SYMPUT scope when the macro CONTAINS a
   computed %GOTO. SAS 9.4 Macro Language: Reference, Fifth Edition, printed
   p.77 ("Special Cases of Scope with the CALL SYMPUT Routine"), rule 2 case 3:

     "If the executing macro contains a computed %GOTO statement, the variable
      will be created in the local symbol table. ... If an executing macro
      contains a computed %GOTO statement ... but the local symbol table is
      empty, CALL SYMPUT behaves as if the local symbol table was not empty,
      and creates a local macro variable."

   A computed %GOTO is "one that uses a label that contains an & or a % in it"
   (p.77; same definition as the printed p.396 footnote). CONTAINS, not
   executes — so a never-taken `%if 1=0 %then %goto &where;` still forces the
   local scope (T1), which is what distinguishes this rule from "the %goto
   ran". The other rules' cases are pinned in macroedge_symput_scopelocal.sas.

   Everything is asserted through DATA-step `put` (stdout): %put writes to
   stderr, which the corpus does not diff. Reverting the fix turns T1-OPEN and
   T2-OPEN into `a token` (wrongly global) and leaves everything else. */

/* T1 — NEVER-EXECUTED computed %GOTO, otherwise-empty local table: the var is
   LOCAL anyway (doc says "contains"), so it resolves inside the macro and is
   dead in open code. */
%macro cg1;
   data _null_;
      call symput('cgvar1', 'a token');
   run;
   data _null_;
      put "T1-INSIDE=[&cgvar1]";
   run;
   %if 1=0 %then %goto &where;
%mend cg1;
%cg1
data _null_;
   put "T1-OPEN=[&cgvar1]";
run;

/* T2 — EXECUTED computed %GOTO to a real label: same scoping, and the branch
   itself still works (skips to the label). The label is computed by a macro
   FUNCTION so the local table stays otherwise empty — a `%local`-based label
   would make the table nonempty and the scope pin vacuous. */
%macro cg2;
   data _null_;
      call symput('cgvar2', 'a token');
   run;
   %goto %substr(done,1,4);
data _null_; put "T2-BAD-not-skipped"; run;
   %done:
   data _null_;
      put "T2-INSIDE=[&cgvar2]";
   run;
%mend cg2;
%cg2
data _null_;
   put "T2-OPEN=[&cgvar2]";
run;

/* T3 control — a PLAIN %goto is not computed and must NOT force the local
   scope: with an otherwise-empty table the var goes GLOBAL, exactly as ENV3. */
%macro cg3;
   %goto done;
data _null_; put "T3-BAD-not-skipped"; run;
   %done:
   data _null_;
      call symput('cgvar3', 'a token');
   run;
%mend cg3;
%cg3
data _null_;
   put "T3-OPEN=[&cgvar3]";
run;

/* T4 control — a computed %GOTO in a COMMENT does not count. */
%macro cg4;
   /* %goto &commented; */
   data _null_;
      call symput('cgvar4', 'a token');
   run;
%mend cg4;
%cg4
data _null_;
   put "T4-OPEN=[&cgvar4]";
run;

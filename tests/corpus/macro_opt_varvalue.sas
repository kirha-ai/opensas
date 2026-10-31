/* BUG-mcompilenotevarlate — a ch.20 macro-family OPTIONS value given as a
   MACRO VARIABLE REFERENCE must take effect at the same point in the stream as
   the same value written as a literal. It used to reach no read-time applier at
   all (applyOptionsStmt could only see a bare literal) and only landed at the
   executor flush, which happens AFTER a following %MACRO in the same chunk has
   already compiled.

   Oracle probes (real SAS 9.4, 2026-11-01):
     - `%let mode=all; options mcompilenote=&mode; %macro q; %put hello; %mend
       q; %q` logs "NOTE: The macro Q completed compilation without errors."
       BEFORE `hello` (ch.20 p.454). Log-only, so it rides along here and is
       pinned by the unit test in src/macro.zig;
     - `options &rep;` with rep=nomreplace draws the NOMREPLACE refusal for the
       NEXT %macro and the ORIGINAL body answers the call (ch.20 p.478);
     - `options sasautos=&dirs;` reports the RESOLVED directory in its own
       error at the OPTIONS statement, i.e. the list is live from there on
       (ch.20 p.482).

   Pins, in output order:
     - SASAUTOS=&dirs + MAUTOSOURCE: the autocall list a macro variable names is
       searchable by an invocation LATER IN THE SAME CHUNK, first listed
       location first — greet exists in BOTH dirs, so tests/autocall2 answers;
     - a macro only the second dir has (shout) still resolves;
     - NOMREPLACE through `options &rep;` refuses the redefinition of m1, so
       %m1 runs the FIRST body ("one", never "two");
     - execution continues afterwards ("after") — a macro-scope error, not an
       errhalt.
   rc 1: the program asked for NOMREPLACE protection and then violated it, the
   same rc tests/corpus/macro_opt_nomreplace.sas pins for the literal form.
   D-017-clean: nothing here writes files.
   expect-rc: 1 */
%let dirs = ('tests/autocall2', 'tests/autocall');
%let rep = nomreplace;
%let note = all;
options mautosource sasautos=&dirs mcompilenote=&note;
%greet(A)
%shout(B)
%macro m1;
  data _null_; put "one"; run;
%mend m1;
options &rep;
%macro m1;
  data _null_; put "two"; run;
%mend m1;
%m1
data _null_; put "after"; run;

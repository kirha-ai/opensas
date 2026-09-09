/* BUG-minoperatoropt: OPTIONS MINOPERATOR [MINDELIMITER='c'] — the SYSTEM-option
   form of the `in`/`#` gate (SAS 9.4). It must behave exactly like the %MACRO
   `/ minoperator` definition option: member and non-member take DIFFERENT
   branches. Before the fix the OPTIONS form was silently ignored AND the
   un-gated `in` fell through to "non-blank text = TRUE", so every operand was
   a member at exit 0. The un-gated (NOMINOPERATOR) `in` is now a loud ERROR —
   pinned by in-file tests in macro.zig (green fixtures only). */

options minoperator mindelimiter=',';

/* macro with no options of its own inherits the system gate + delimiter */
%macro g(x);
  %if &x in a,b,c %then %let r = member;
  %else %let r = nonmember;
  data _null_;
    put "&x=&r";
  run;
%mend;
%g(b)
%g(q)
%g(B)

/* %eval agrees with %if on the same text under the system gate */
data _null_;
  put "v1=%eval(b in a,b,c)";
  put "v2=%eval(q in a,b,c)";
run;

/* the / minoperator definition option still wins on its own, and a macro
   defined with MINDELIMITER= overrides the system one for its own body.
   (The delimiter here avoids ';' — a semicolon inside a %if condition
   truncates the branch scan, a pre-existing scanner limitation.) */
options mindelimiter=' ';
%macro h(x) / minoperator mindelimiter=':';
  %if &x in a:b:c %then %let r2 = member;
  %else %let r2 = nonmember;
  data _null_;
    put "&x=&r2";
  run;
%mend;
%h(a)
%h(z)

/* gate OFF after OPTIONS NOMINOPERATOR: text compares still work (the loud
   `in` error that state now raises is pinned in macro.zig) */
options nominoperator;
%macro n(x);
  %if &x = q %then %let r3 = is-q;
  %else %let r3 = not-q;
  data _null_;
    put "&x=&r3";
  run;
%mend;
%n(q)
%n(b)

/* BUG-macroinoperator: the `in`/`#` macro operator tests whether the left
   operand equals one of the (blank-)delimited items on the right. It is a
   special operator ONLY when the enclosing %MACRO was defined `/ minoperator`
   (SAS 9.4 default is NOMINOPERATOR); MINDELIMITER= overrides the delimiter.
   Member and non-member must take DIFFERENT branches. */

/* /minoperator ON — blank-delimited list; case-sensitive */
%macro mem(x) / minoperator;
  %if &x in a b c %then %let r = member;
  %else %let r = nonmember;
  data _null_;
    put "&x=&r";
  run;
%mend;
%mem(b)
%mem(z)
%mem(B)

/* MINDELIMITER=',' — comma-delimited list */
%macro memc(x) / minoperator mindelimiter=',';
  %if &x in a,b,c %then %let r = member;
  %else %let r = nonmember;
  data _null_;
    put "&x=&r";
  run;
%mend;
%memc(c)
%memc(z)

/* MINOPERATOR OFF (default): `%if &x in a b c` is NOT a membership test — the
   un-gated `in` makes the condition the SAME invalid macro expression %eval
   rejects, so it is a loud ERROR (BUG-minoperatoropt: %if agrees with %eval;
   the old always-true fallthrough let every operand take %then at exit 0).
   Loud half pinned by in-file tests in macro.zig — green fixtures only. The
   OPTIONS-statement form of the gate is pinned by macro_minoperator_opt. */

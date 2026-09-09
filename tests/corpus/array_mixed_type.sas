/* BUG-mixedtypearray: an ARRAY's elements must be ALL numeric or ALL
   character — SAS 9.4 errors at compile time ("Variable x2 has been defined
   as both character and numeric."). A mixed member list used to be silently
   accepted: the char member kept its type and a subscripted write to it was
   silently converted/dropped. The ERROR is on stderr (asserted via captured
   diagnostics in exec.zig's test); stdout pins the HALT: the bad step writes
   nothing, and the VALID all-numeric / all-char arrays above still run.
   expect-rc: 1 */

data _null_;
  array n{2} n1 n2 (10 20);      /* all-numeric — legal */
  array c{2} $ c1 c2 ('p' 'q');  /* all-char — legal */
  n{2} = n{2} + 1;
  c{2} = 'z';
  put n1= n2= c1= c2=;
run;

data _null_;
  x1 = 1;
  x2 = 'ab';
  array mix{2} x1 x2;  /* ERROR: char x2 in a numeric array — mixed types */
  mix{2} = 2;
  put 'never-runs';    /* the step halts before a single observation */
run;

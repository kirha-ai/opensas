/* D-009a: ABORT is the EXCEPTION to the 0/1/2 contract — the user's return code
   becomes the process exit code, so this program must exit 3 and NOT 1. That is
   the only rc in the tree a downstream agent must NOT route on, and until
   BUG-nofixturepinsrc nothing outside a unit test could hold it.
   expect-rc: 3 */
data a;
  x = 1;
  put 'before abort';
  abort return 3;
  put 'unreachable';
run;
data b;
  y = 2;
  put 'AFTER ABORT — must not run';
run;
proc print data=a;
run;

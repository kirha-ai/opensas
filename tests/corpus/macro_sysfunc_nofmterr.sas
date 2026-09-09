/* BUG-sysfuncnofmterrclobber: `%sysfunc(fn(), fmt.)` BORROWS format.zig's
   NOFMTERR flag to suppress its own "format not found", then used to hand it back
   as the CONSTANT `false` — silently switching the user's `options nofmterr;` back
   ON. The unknown format in the LAST step is the victim: pre-fix it reported
   `ERROR: The format nosuchfmt was not found or could not be loaded.` and the
   program exited 1, for an option the program had explicitly turned off.

   The middle step is load-bearing, not padding: macro expansion INTERLEAVES with
   execution (D-004), so without a step between them the %sysfunc is expanded
   BEFORE the OPTIONS statement ever runs and the clobber lands on a flag that is
   already false — invisible. Delete that step and this fixture stops testing
   anything.
   expect-rc: 0 */
options nofmterr;
data _null_;
  put 'nofmterr in effect';
run;
%let d = %sysfunc(abs(-5), nosuchfmt.);
data _null_;
  y = 2;
  put "d=[&d]";
  put y nosuchfmt8.;
run;

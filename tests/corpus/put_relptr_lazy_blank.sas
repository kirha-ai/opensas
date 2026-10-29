/* NOTE-putrelskipblank / BUG-putptrtailpad: real SAS 9.4 oracle via
   /Users/argos/saspy/bin/sasrun confirms positioning alone emits no bytes:
   `put x +(-2) "!"` writes 34 21 0A, and tail controls like `put x @5;`,
   `put x +0;`, and `put 'ab' @5;` end at the last written column. For live
   SAS, write/read through a TEMP fileref; this fixture's .zig-cache path is
   relative to the opensas runner cwd and not sasrun's server cwd. */
data _null_;
  file ".zig-cache/put_relptr_lazy_blank_out.txt";
  x = 42;
  put x +(-2) "!";
  put x +0 "!";
  put x +1 "!";
  put x +(-1) ".";
  put x @5;
  put x +0;
  put 'ab' @5;
  put x @3;
  put @5 'x';
run;

data _null_;
  infile ".zig-cache/put_relptr_lazy_blank_out.txt";
  input;
  put _infile_ $hex.;
run;

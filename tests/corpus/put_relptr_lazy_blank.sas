/* NOTE-putrelskipblank: real SAS 9.4 oracle via
   /Users/argos/saspy/bin/sasrun writes bytes 34 21 0A for
   `put x +(-2) "!"` through FILE. The list-style separator after x is a
   virtual column for relative pointer arithmetic, not a materialized tail byte
   when a backward +(-n) crosses it. */
data _null_;
  file ".zig-cache/put_relptr_lazy_blank_out.txt";
  x = 42;
  put x +(-2) "!";
  put x +0 "!";
  put x +1 "!";
  put x +(-1) ".";
run;

data _null_;
  infile ".zig-cache/put_relptr_lazy_blank_out.txt";
  input;
  put _infile_ $hex.;
run;

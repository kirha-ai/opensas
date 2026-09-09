/* COUNTC character-class modifiers (d/u/l/...) count a whole class.
   Regression guard for BUG-countcmodifiers. */
data _null_;
  a = countc("a1b2c3", "", "d");
  b = countc("aAbBcC", "", "u");
  c = countc("Hello World", "", "l");
  d = countc("abc123", "abc");
  e = countc("a1b2", "", "d", "v");
  put "digits=" a;
  put "upper=" b;
  put "lower=" c;
  put "lit=" d;
  put "notdigit=" e;
run;

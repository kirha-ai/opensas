/* FINDC character-class modifiers (d/u/l/a/s...) add a whole class to the search
   list. Regression guard for BUG-findcmodifiers. */
data _null_;
  a = findc("abc123", " ", "d");
  b = findc("abcABC", " ", "u");
  c = findc("ABCabc", "", "l");
  d = findc("123abc", " ", "a");
  e = findc("hello world", "", "s");
  f = findc("abc", " ", "d");
  put "digit=" a;
  put "upper=" b;
  put "lower=" c;
  put "alpha=" d;
  put "space=" e;
  put "none=" f;
run;

/* COUNT i (case-insensitive) and t (trim) modifiers.
   Regression guard for BUG-countmodifiers. */
data _null_;
  a = count("aAaA", "a", "i");
  b = count("abab", "AB", "i");
  c = count("abab", "ab ", "t");
  d = count("aAaA", "a");
  e = count("abcabc", "bc");
  f = count("aAaA", "A", "it");
  put "ci_a=" a;
  put "ci_ab=" b;
  put "trim=" c;
  put "plain=" d;
  put "plain2=" e;
  put "combo=" f;
run;

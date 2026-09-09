/* BUG-comparemods: COMPARE honors only the `i` modifier and silently ignores
   `l` (strip leading blanks) and `:` (truncate longer to shorter length).
   SAS values: a=0, b=0, c=0 (il combo: leading blanks + case), d=-1 (no-mod
   control: '  abc' vs 'abc' differ at position 1, blank < 'a'),
   e=4 (plain prefix compare, blank-padded), f=0 (colon + i). */
data _null_;
  a = compare('  abc', 'abc', 'l');
  b = compare('abcdef', 'abc', ':');
  c = compare('  ABC', 'abc', 'il');
  d = compare('  abc', 'abc');
  e = compare('abcdef', 'abc');
  f = compare('ABCdef', 'abc', ':i');
  put a= b= c=;
  put d= e= f=;
run;

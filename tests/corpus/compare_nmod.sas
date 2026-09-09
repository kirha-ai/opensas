/* BUG-comparenmod: COMPARE `n` modifier (funcref p.526) dequotes a name
   literal ("text"n -> text, or bare "text") AND ignores case. SAS values:
   a=0 (name-literal quotes stripped -> equal), b=0 (n implies case-insensitive),
   c=0 ("abc"n suffix form dequotes to abc), d=-3 (still differs at pos 3 under n),
   e=-1 (no-mod control: quoted "abc" vs abc differ at position 1, '"' < 'a'). */
data _null_;
  a = compare('"abc"', 'abc', 'n');
  b = compare('ABC', 'abc', 'n');
  c = compare('"abc"n', 'ABC', 'n');
  d = compare('abc', 'abd', 'n');
  e = compare('"abc"', 'abc');
  put a= b= c=;
  put d= e=;
run;

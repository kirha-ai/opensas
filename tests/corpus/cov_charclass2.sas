data _null_;
  c1=anyname('  a1'); c2=anyfirst('1ab'); c3=anygraph('  x'); c4=anyprint('abc');
  c5=notfirst('a1b'); c6=notgraph('ab '); c7=notname('ab*'); c8=notprint('abc');
  c9=notpunct('.,a'); c10=notspace('  x'); c11=notupper('ABc'); c12=notxdigit('12g');
  put "cc1=" c1 c2 c3 c4;
  put "cc2=" c5 c6 c7 c8;
  put "cc3=" c9 c10 c11 c12;
run;

data _null_;
  /* CALL SCAN routes through the SCAN function machinery (BUG-callscanstale):
     the 'm' modifier keeps empty words and the default delimiter set matches
     SCAN() (so '>' is not a delimiter). */
  call scan('a,,b,c', 2, p, l, ',', 'm');
  put "m_mod pos=" p " len=" l;

  call scan('aa>bb>cc', 2, p2, l2);
  put "gt pos=" p2 " len=" l2;

  call scan('a b c', 2, p3, l3);
  put "plain pos=" p3 " len=" l3;
run;

data _null_;
  /* CALL STDIZE METHOD=RANGE (BUG-callstdizemethod): (x-min)/(max-min) */
  a=2; b=4; c=6;
  call stdize('method=range', a, b, c);
  put "range=" a b c;
  /* default (no option) still METHOD=STD */
  x=2; y=4; z=6;
  call stdize(x, y, z);
  put "std=" x y z;
run;

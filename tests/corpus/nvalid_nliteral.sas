/* BUG-nvalidnliteral (doc-finder tick243 F1/F2): NVALID honors its 2nd
   argument (V7/ANY/NLITERAL/UPCASE) and trims only TRAILING blanks — a
   LEADING blank makes a name invalid. NLITERAL returns an already-valid V7
   name unchanged, else quotes per doc p.1225-1226: SINGLE quotes when the
   string contains &, %, or more " than '; double quotes otherwise. */
data _null_;
  n1 = nvalid('abc');            /* 1  default = V7 */
  n2 = nvalid('abc', 'V7');      /* 1  explicit V7 */
  n3 = nvalid('2bc', 'V7');      /* 0  digit start */
  n4 = nvalid(' abc', 'V7');     /* 0  LEADING blank is data (no left-trim) */
  n5 = nvalid('abc ', 'V7');     /* 1  trailing blank ignored */
  n6 = nvalid('a b', 'ANY');     /* 1  ANY: 1-32 bytes of anything */
  n7 = nvalid('foo-bar', 'any'); /* 1  keyword case-insensitive */
  n8 = nvalid('a b', 'V7');      /* 0  embedded blank not V7 */
  n9 = nvalid("'a b'n", 'NLITERAL'); /* 1  name-literal form */
  n10 = nvalid('abc', 'NLITERAL');   /* 0  not in literal form */
  put n1= n2= n3= n4= n5= n6= n7= n8= n9= n10=;

  l1 = nliteral('abc');         /* abc           valid V7 name, unchanged */
  l2 = nliteral('a b');         /* "a b"n        double by default */
  l3 = nliteral('2x');          /* "2x"n         digit start, quoted */
  l4 = nliteral('cats & dogs'); /* 'cats & dogs'n  & forces single quotes */
  l5 = nliteral("it's");        /* "it's"n       more ' than " -> double */
  put l1= l2= l3= l4= l5=;
run;

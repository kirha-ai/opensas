/* QA regression (BUG-prxquant, dev2 2d10596): PRX bounded quantifiers {n}/{n,}/
   {n,m} and word boundaries \b/\B. prxmatch returns 1-based match start, 0=none. */
data _null_;
  a=prxmatch('/a{2}/', 'baaa');
  b=prxmatch('/a{2,}/', 'baaa');
  c=prxmatch('/a{2,3}/', 'baaaa');
  d=prxmatch('/[0-9]{3}/', 'ab123');
  e=prxmatch('/a{2}/', 'xa{2}y');
  f=prxmatch('/\bcat\b/', 'the cat sat');
  g=prxmatch('/\Bcat/', 'scatter');
  h=prxmatch('/[0-9]{3}-[0-9]{4}/', 'call 555-1234 now');
  put "a{2}=" a;
  put "a{2,}=" b;
  put "a{2,3}=" c;
  put "digits{3}=" d;
  put "literal=" e;
  put "boundary=" f;
  put "nonboundary=" g;
  put "phone=" h;
run;

data _null_;
  /* named-variable write-back */
  a=3; b=1; c=2;
  call sortn(a, b, c);
  put "named=" a b c;
  /* subscripted array-element write-back */
  array p{3} p1-p3 (30 10 20);
  call sortn(p{1}, p{2}, p{3});
  put "subscript=" p1 p2 p3;
  /* of array[*] write-back */
  array q{3} q1-q3 (5 3 4);
  call sortn(of q{*});
  put "ofstar=" q1 q2 q3;
  /* CALL RANUNI fills a var by reference; CALL VNAME writes the name */
  seed=1;
  call ranuni(seed, r);
  inrange=(r>0 and r<1);
  call vname(a, nm);
  put "ranuni_in01=" inrange "vname=" nm;
run;

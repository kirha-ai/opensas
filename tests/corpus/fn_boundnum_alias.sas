/* Numbered-suffix array-bound aliases: dimN(a) === dim(a,N), and likewise
   hboundN/lboundN (GAP-arraybounds-batch). On a [2,3] array dim1/dim2 give
   2/3, hboundN the per-dimension upper bound, lboundN the lower bound; the
   aliases must also see an explicit (negative) lower bound. */
data _null_;
  array m[2,3] m1-m6 (1 2 3 4 5 6);
  d1=dim1(m); d2=dim2(m);
  h1=hbound1(m); h2=hbound2(m); l1=lbound1(m); l2=lbound2(m);
  put "dims=" d1 d2;
  put "hb=" h1 h2 " lb=" l1 l2;
  array b[-2:2] b1-b5;
  bl=lbound1(b); bh=hbound1(b); bd=dim1(b);
  put "negbounds=" bl bh bd;
  array p[4] p1-p4;
  pd=dim1(p); pl=lbound1(p); ph=hbound1(p);
  put "plain=" pd pl ph;
run;

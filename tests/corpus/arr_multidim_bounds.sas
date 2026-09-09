/* Multi-dim array with an explicit non-1 lower bound, queried via the two-arg
   DIM/HBOUND/LBOUND(array, dimension) forms. Row-major fill (rightmost subscript
   varies fastest) means the flat member list b1..b6 holds row 1 then row 2, and
   the lower-bound offset must land b[2,3] on the last member (ARRAY-lobound +
   GAP-multidimarray). Easy to get the offset fold wrong. */
data _null_;
  array b[2:3, 3] b1-b6;
  n=0;
  do i=2 to 3; do j=1 to 3; n+1; b[i,j]=n*10; end; end;
  d1=dim(b,1); d2=dim(b,2);
  lb1=lbound(b,1); hb1=hbound(b,1); lb2=lbound(b,2); hb2=hbound(b,2);
  put "dims=" d1 d2 " bound1=" lb1 hb1 " bound2=" lb2 hb2;
  put "flat=" b1 b2 b3 b4 b5 b6;
  put "ref b[2,1]=" b[2,1] " b[3,3]=" b[3,3];
run;

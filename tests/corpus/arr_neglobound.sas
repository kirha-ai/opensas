/* Negative array lower bound: array b[-2:2] declares 5 members addressed
   b{-2}..b{2}; the lower-bound offset must fold so b{-2} lands on the FIRST
   member and b{2} on the last, and lbound/hbound/dim report -2/2/5
   (GAP-arraybounds-batch). */
data _null_;
  array b[-2:2] b1-b5 (10 20 30 40 50);
  x1=b{-2}; x2=b{-1}; x3=b{0}; x4=b{1}; x5=b{2};
  l=lbound(b); h=hbound(b); d=dim(b);
  put "elems=" x1 x2 x3 x4 x5;
  put "bounds=" l h d;
  array c[-5:-2] c1-c4 (1 2 3 4);
  y1=c{-5}; y4=c{-2}; cl=lbound(c); ch=hbound(c);
  put "negrange=" y1 y4 cl ch;
run;

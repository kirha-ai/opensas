/* CALL LEXPERM/LEXPERK/LEXCOMBI/GRAYCODE + CALL SORT. Phase-F-callbatch. */
data _null_;
  do i=1 to 6; a=1;b=2;c=3; call lexperm(i,a,b,c); put "lexperm" i "=" a b c; end;
  do i=1 to 6; x=1;y=2;z=3; call lexperk(i,2,x,y,z); put "lexperk" i "=" x y; end;
  i1=0;i2=0; do j=1 to 6; call lexcombi(4,2,i1,i2); put "lexcombi" j "=" i1 i2; end;
  g1=0;g2=0;g3=0;k=0; do j=1 to 7; call graycode(k,g1,g2,g3); put "gray" j "=" g1 g2 g3 " k=" k; end;
  p=3;q=1;r=2; call sort(p,q,r); put "sort=" p q r;
run;

/* Function-form combinatorics: rc = allcomb/allperm/graycode/lexcomb/lexcombi/
   lexperk/lexperm/sort(...). Mutate the variable args + return SAS's status
   (leftmost-changed index, subset size for graycode, 1 for sort). Phase-F-final. */
data _null_;
  do i=1 to 6; a=1;b=2;c=3; rc=allperm(i,a,b,c); put "allperm" i "=" a b c " rc=" rc; end;
  do i=1 to 3; x=1;y=2;z=3; rc=allcomb(i,2,x,y,z); put "allcomb" i "=" x y " rc=" rc; end;
  do i=1 to 6; p=1;q=2;r=3; rc=lexperm(i,p,q,r); put "lexperm" i "=" p q r " rc=" rc; end;
  do i=1 to 6; u=1;v=2;w=3; rc=lexperk(i,2,u,v,w); put "lexperk" i "=" u v " rc=" rc; end;
  do i=1 to 3; d=1;e=2;f=3; rc=lexcomb(i,2,d,e,f); put "lexcomb" i "=" d e " rc=" rc; end;
  i1=0;i2=0; do i=1 to 6; rc=lexcombi(4,2,i1,i2); put "lexcombi" i "=" i1 i2 " rc=" rc; end;
  g1=0;g2=0;g3=0; do i=1 to 4; k=graycode(k,g1,g2,g3); put "gray" i "=" g1 g2 g3 " k=" k; end;
  array arr[3] p1-p3 (3 1 2);
  j=sort(of arr[*]);
  put "sort_array=" p1 p2 p3 " j=" j;
run;

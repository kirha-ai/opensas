/* QA r24: CALL SORTN / CALL SORTC uncovered surface — in-place ascending sort of
   the argument list. Numeric missing sorts first; char sorts by collation.
   Verified against SAS 9.4. */
data _null_;
  a=3; b=.; c=1; d=2;
  call sortn(a,b,c,d);
  put 'sortn:' a= b= c= d=;
  length p q r s $4;
  p="pear"; q="apple"; r="date"; s="fig";
  call sortc(p,q,r,s);
  put 'sortc:' p= q= r= s=;
run;

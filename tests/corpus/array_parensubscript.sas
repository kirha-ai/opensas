/* GAP-arrayparensubscript: SAS 9.4 accepts ()/{}/[] interchangeably for array
   subscripting. a(i) was rejected as "function a() not supported"; now it reads
   the array member like a{i} / a[i]. */
data _null_;
  array a{3} x1-x3 (1 2 3);
  do i=1 to 3;
    v=a(i);
    put v=;
  end;
  a(2)=99;
  w=a(2);
  put w=;
run;

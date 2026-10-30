/* PERF-prxprxparsepercall: SAS 9.4 compiles a literal PRXPARSE once per
   source call site. Distinct sites get distinct IDs; a variable pattern
   compiles each time, even when its text is unchanged. */
data _null_;
  do i=1 to 3;
    a=prxparse('/abc/');
    b=prxparse('/abc/');
    p='/abc/';
    c=prxparse(p);
    put i= a= b= c=;
  end;
  call prxfree(a);
  m=prxmatch(b, 'abc');
  put m=;
  do j=1 to 3;
    rx=prxparse('/x/');
    mt=prxmatch(rx, 'x');
    put j= rx= mt=;
    call prxfree(rx);
  end;
run;

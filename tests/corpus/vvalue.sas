/* VVALUE / VVALUEX: render a value with its (default) format. Phase-F. */
data _null_;
  n = 3.14;
  c = "hello";
  length id 8;
  id = 42;
  putn = vvalue(n);
  putc = vvalue(c);
  putx = vvaluex("id");
  put "num="  putn;
  put "char=" putc;
  put "byname=" putx;
run;

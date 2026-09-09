/* CALL PRXSUBSTR/PRXPOSN/PRXCHANGE/PRXNEXT/PRXFREE via the prx.zig engine.
   Phase-F-callbatch. */
data _null_;
  length s $40 r $40 t $40;
  rx = prxparse('/(\d+)-(\d+)/');
  s = "code 12-345 end";
  call prxsubstr(rx, s, pos, len);
  put "substr=" pos " " len;
  call prxposn(rx, 1, p1, l1);
  call prxposn(rx, 2, p2, l2);
  put "posn1=" p1 " " l1;
  put "posn2=" p2 " " l2;
  r = "a1b2c3";
  rx2 = prxparse('s/\d/X/');
  call prxchange(rx2, -1, r);
  put "change=" r;
  rx3 = prxparse('/\d/');
  t = "a1b2c3"; bg=1; en=6;
  call prxnext(rx3, bg, en, t, po, le);
  put "next1=" po " " bg;
  call prxnext(rx3, bg, en, t, po, le);
  put "next2=" po;
  call prxfree(rx);
  put "freed=" rx;
run;

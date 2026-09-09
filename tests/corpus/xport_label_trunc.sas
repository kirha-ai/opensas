/* GAP-xportio-low F11: an XPORT label over the v5 nlabel field's 40 chars
   truncates at EXACTLY 40 (format-forced; SAS labels run to 256) and the
   write WARNS — the loud half is pinned by xport.zig's in-file test with a
   captured reporter (the warning rides stderr, which the corpus does not
   diff). This pins the visible half end-to-end: write → read back fresh →
   CONTENTS shows the label at exactly 40 characters. */
data d;
  x = 1;
  label x = "A label that is definitely longer than forty characters total";
run;
libname o xport "tests/corpus/includes/xport_label_trunc.xpt";
proc copy in=work out=o; select d; run;
libname r xport "tests/corpus/includes/xport_label_trunc.xpt";
data back; set r.d; run;
proc contents data=back; run;

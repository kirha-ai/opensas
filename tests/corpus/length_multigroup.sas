/* audit-tick: length_stmt — several var-groups in one LENGTH, mixed char/num,
   and a numbered range d1-d3 all take their group length. */
data d;
  length a b $ 8 c 4 d1-d3 8;
  a = "1234567890"; c = 1.5; d2 = 7;
  put a= c= d2=;
run;
proc contents data=d; run;

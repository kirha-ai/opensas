/* GAP-arraysum: `a[i] + expr;` is a SUM statement on an array element —
 * the subscripted analog of `var + expr;`. The element is retained across
 * iterations and expr is added each execution (init 0). */
data src;
  input cat val;
  datalines;
1 10
1 5
2 100
;
run;
data _null_;
  array t[3];
  do i = 1 to 3;
    t[i] + i;
  end;
  put t1= t2= t3=;
run;
data _null_;
  set src end = last;
  array cnt[2] _temporary_;
  cnt[cat] + val;
  if last then put _temp_cnt_1= _temp_cnt_2=;
run;

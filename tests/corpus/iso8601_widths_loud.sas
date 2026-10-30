/* BUG-8601widths: ISO 8601 format/informat widths outside their documented
   ranges are user-program errors, not silently accepted truncation/overflow.
   expect-rc: 1 */
data _null_;
  d = mdy(7,4,2020);
  dt = dhms(d,14,5,6);
  t = hms(14,5,6);
  put "BEFORE: runs";
  a = put(d, e8601da5.);
  b = put(dt, e8601dn12.);
  c = put(t, e8601tm16.);
  e = put(d, b8601da7.);
  f = put(dt, b8601dt14.);
  g = put(t, b8601tm16.);
  h = input("2020-07-04", e8601da12.);
  i = input("14:05:06", e8601tm7.);
  j = input("20200704T140506", b8601dt14.);
  k = input("140506", b8601tm5.);
run;

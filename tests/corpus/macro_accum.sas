/* PERF-macroaccum regression: accumulating a macro var via `%let s=&s tok;`
   in a %do loop must produce the SAME final value (the O(M^2)->O(live) RAM fix
   is by construction — owned reusable buffers; M modest so the corpus stays
   fast — a huge-M probe would OOM it). */
%macro accum;
%let s=;
%do i=1 %to 300;
  %let s=&s.x;
%end;
data _null_;
  v = "&s";
  l = length(v);
  t = substr(v, 298, 3);
  put "len=" l " tail=" t;
run;
%mend;
%accum

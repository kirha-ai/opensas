/* BUG-todinformat: TODw. as an INPUT-statement informat reads a time-of-day to a
   SAS time (seconds since midnight) — it was whitelisted as "known" with no read
   branch, so every field silently read MISSING while the TOD *format* rendered
   the same value correctly. Round-trip below: read with tod18., write back with
   tod8., so a read/write disagreement shows up on the same line.
   A datetime field (last-but-one data line) keeps only its time-of-day — that
   extraction is the whole reason TOD sits next to TIME.

   The rt/tm/f columns also pin the two write-side rules TOD does NOT share with
   TIME (both fixed after this fixture first landed):
   NOTE-todhourpad — TOD zero-pads a single-digit hour, TIME blank-pads it. Language Reference: Concepts'
     format tables print both on the same input: `TIME. 19434 -> 5:23:54` next to
     `TOD. 19434 -> 05:23:54` (printed p.147 "Time formats", repeated p.150). The
     `7` and `12:00 AM` rows are that contrast; we used to blank-pad both.
   NOTE-todfloorfrac — TODw.d floored its input, so `.d` could never render
     fractional seconds and TOD disagreed with TIME on rounding. The `01:30:45.5`
     row pins the agreement: rt and tm round alike, and f shows the `.d`. */
data _null_;
  infile datalines truncover;
  input a tod18.;
  rt = put(a, tod8.);   /* TOD hour: zero-padded */
  tm = put(a, time8.);  /* TIME hour: blank-padded — the documented contrast */
  f  = put(a, tod11.1); /* d=1: fractional seconds render */
  put a= rt= tm= f=;
datalines;
10:30:00
14:45
7
1:30 PM
12:00 AM
01:30:45.5
25DEC2024:10:30:00
not a time
;
run;

/* BUG-tzonesilentignore: an EXPLICIT 'UTC' (any case) or blank time-zone
   argument is honored (opensas keeps wall-clock in UTC — see src/datefns.zig);
   the zero-argument current-zone forms live in tzone_utc. A NAMED non-UTC zone
   now fails loud (D-002) instead of silently answering for UTC — asserted in
   the captured-diagnostics unit test in src/datefns.zig. */
data _null_;
  length id $8 nm $8;
  id = tzoneid('UTC');
  nm = tzonename('utc');
  o1 = tzoneoff('UTC');
  o2 = tzoneoff('');          /* blank zone = the current zone (UTC) */
  u  = tzones2u(1893456000, 'UTC');
  s  = tzoneu2s(1893456000, 'Utc');
  put id= nm= o1= o2= u= s=;
run;

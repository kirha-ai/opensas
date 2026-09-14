/* GH#5 ISS-informatfallback: the INPUT() FUNCTION path used to fall back to
   plain numeric parsing when the informat did not load — `input('2025',
   zzznotreal.)` printed "ERROR: The informat zzznotreal was not found or
   could not be loaded." and then STILL returned 2025 (plausible-but-wrong).
   Language Reference: Concepts p.518 "How SAS Handles Invalid Data" (pdf idx 535):
   a value requiring an informat that is not available is INVALID — set the
   value to MISSING, print the invalid-data NOTE (stderr; no "at line N column
   M" tail: ast.Call nodes carry no source span, GH#78 precedent), and set
   _ERROR_ to 1. The INPUT STATEMENT path already did all four (io.zig
   checkInputInformats + noteInvalidNum, pinned by informat_unknown_halts /
   informat_char_unknown); this fixture pins the function-path twin. A blank /
   `.` / special-missing source stays a SILENT missing (legitimate, not
   invalid — the same guard io.zig noteInvalidNum draws).
   expect-rc: 1 */
data _null_;
  b = input('2025', zzznotreal.);
  put "b=[" b "]";
  if _error_ then put "ERRORVAR=1";
  else put "ERRORVAR=0";

  /* blank and coded-missing sources: missing WITHOUT a NOTE or _ERROR_ */
  c = input(' ', zzznotreal.);
  d = input('.', zzznotreal.);
  e = input('.k', zzznotreal.);
  put "c=[" c "] d=[" d "] e=[" e "]";

  /* the INPUTN twin NOTEs under its own name; value still missing */
  g = inputn('2025', zzznotreal.);
  put "g=[" g "]";

  /* a KNOWN informat is untouched — reads through, _ERROR_ stays set only
     from the invalid read above (the executor resets it per iteration) */
  f = input('2025', 4.);
  put "f=[" f "]";
run;

/* GH#4a ISS-inputfninvalid: the `?`/`??` modifiers are part of the call
   (INPUT(source, <?|??> informat.), Functions-ref printed pp.1038-39).
   `?` suppresses the invalid-data NOTE but keeps _ERROR_=1 (doc Example 3
   prints _ERROR_=1 under `?`); `??` silences both. The loud informat-not-
   loaded ERROR is NOT invalid-data messaging — it fires at every level. */
data _null_;
  q = input('2025', ? zzznotreal.);
  put "Q=[" q "]";
  if _error_ then put "Q_ERR=1"; else put "Q_ERR=0";
run;
data _null_;
  r = input('2025', ?? zzznotreal.);
  put "R=[" r "]";
  if _error_ then put "R_ERR=1"; else put "R_ERR=0";
run;

/* rider: a KNOWN informat failing on non-blank data is invalid data too —
   `input('abc', 4.)` used to be a SILENT missing with _ERROR_=0 on this
   path. Level 0 notes + flags; `?` keeps the flag; `??` silences both, and
   does NOT clear a flag an earlier error raised (the executor resets
   _ERROR_ per iteration, as the step boundary below shows). */
data _null_;
  s = input('abc', 4.);
  t = input('abc', ? 4.);
  put "S=[" s "] T=[" t "]";
  if _error_ then put "ST_ERR=1"; else put "ST_ERR=0";
run;
data _null_;
  u = input('abc', ?? 4.);
  put "U=[" u "]";
  if _error_ then put "U_ERR=1"; else put "U_ERR=0";
run;

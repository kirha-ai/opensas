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

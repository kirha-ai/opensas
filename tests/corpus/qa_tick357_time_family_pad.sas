/* QA tick357 — renderTod now ROUTES THROUGH renderTime (938e89b8,
   NOTE-todhourpad/NOTE-todfloorfrac). renderTime is SHARED by TIME, NLTIME and
   E8601TM, and its `zero_pad_hour` flag is exactly the thing TOD flipped — so a
   future edit to that shared body can silently move a sibling format that no
   TOD fixture would notice. This pins the WHOLE family on one input, so the
   siblings are a positive control for any later renderTime change.

   Doc anchor: Language Reference: Concepts printed p.147 ("Time formats") and again p.150 ("Write SAS
   time values as time values") list these rows on the SAME input, 19434:
     HHMM.     19434  5:24
     HOUR.     19434  5
     MMSS.     19434  323
     TIME.     19434  5:23:54
     TIMEAMPM. 19434  5:23:54 AM
     TOD.      19434  05:23:54
   TOD is the ONLY one of the six that zero-pads the leading hour; the other
   five keep the bare single-digit hour. That contrast is the invariant here.

   AMENDED (NOTE-timedefwidth): that invariant is about ZERO-padding and still
   holds — but it is NOT about field width, and `time_def` originally pinned the
   wrong thing. SAS 9.4 Formats and Informats: Reference p.478 gives TIMEw.d
   `w Default 8`, and p.479 says twice that a single-digit hour gets a LEADING
   BLANK. So width-less `time.` is `time8.` — ` 5:23:54`, not `5:23:54`. The
   Language Reference: Concepts p.147 row above does not contradict that: a table CELL cannot render
   leading whitespace, exactly as the Formats entry's own inline example
   ("writes 9:00 instead of 09:00") cannot. TOD zero-pads, TIME blank-pads. */
data t;
  x = 19434;
  hhmm     = put(x, hhmm5.);
  hour     = put(x, hour4.);
  mmss     = put(x, mmss5.);
  time     = put(x, time8.);
  timeampm = put(x, timeampm11.);
  tod      = put(x, tod8.);
  /* the bare-width (default) forms of the pair the doc prints side by side */
  time_def = put(x, time.);
  tod_def  = put(x, tod.);
  /* the OTHER zero-padding renderTime caller (ISO) and the OTHER blank-padding
     one (NL) — neither may drift when TOD's flag is touched */
  iso      = put(x, e8601tm8.);
  nltime   = put(x, nltime.);
run;
proc print data=t noobs; var hhmm hour mmss time timeampm tod; run;
proc print data=t noobs; var time_def tod_def iso nltime; run;

/* NOTE-todfloorfrac: renderTod used to @floor before the mod, which made TODw.d
   incapable of fractional seconds and split TOD from TIME on rounding. The two
   must now agree on the rounded whole-second value and TOD must keep `.d`. */
data f;
  x = 5445.5;
  time  = put(x, time8.);    /* rounds to 1:30:46 */
  tod   = put(x, tod8.);     /* same rounding, zero-padded hour */
  tod_d = put(x, tod10.1);   /* the fraction survives */
run;
proc print data=f noobs; run;

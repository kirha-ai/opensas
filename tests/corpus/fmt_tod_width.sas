/* NOTE-todnarrowwidth: TODw.d at NON-default widths (2..20, and .d). Filed as
   "TOD4./TOD7./TOD10.2 drop a component" — probed against SAS 9.4 Formats and
   Informats: Reference (TODw.d, printed p.483-485, pdf 496-498 of
   the Formats and Informats reference). Result: NO divergence found, current
   renders match every anchor the entry gives; this fixture pins that verdict
   on its own set of times (a 2-digit hour, a 1-digit hour, a fractional value
   and a past-midnight value).

   Doc rules quoted:
   - w: "Default 8, Range 2-20" (p.483; en dash in the original).
   - d: "specifies the number of digits to the right of the decimal point in the
     seconds value ... Default 0, Range 0-19. Requirement: d must be less than w."
   - "The TODw.d format writes a leading 0 for a single-hour digit. The TIMEw.d
     format and the HHMMw.d format write a leading blank" (p.484 Comparisons) —
     the zero-padded hour is UNCONDITIONAL, so it costs a column at w=4/7 for a
     single-digit hour. That cost IS the reported "dropped component": `  03`,
     not `3:15`, is the conformant TOD4 render.
   - Worked examples: `put mydt1 tod5.;` -> `14:20` and `put mydt2 tod9.;` ->
     ` 01:30:00` (p.484-485): components render whole (hh / hh:mm / hh:mm:ss),
     right-aligned; never truncated mid-component.
   - d-fit: the seconds fraction needs w >= 8+1+d (TIMEw.d tip, p.479: "three
     decimal places ... at least 12 spaces"), so TOD10.2 (needs 11) drops the
     `.ff` and right-aligns `17:45:23`; TOD11.2 keeps it.
   - MOD note (p.483): "if you give TOD a value of '25:00:00't, it formats the
     value as 1:00:00" — value wraps MOD 24:00:00. (The note prints the hour
     bare; the zero-pad anchors — Comparisons, the tod9. example, and Language Reference: Concepts'
     `TOD. 19434 -> 05:23:54` — outvote it 3-to-1, so `02:15:00` is pinned for
     the 26:15:00 value below.)
   DOC-SILENT widths: 3, 4, 6, 7 for a 2-digit hour and 4, 6, 7 for a 1-digit
   hour have no explicit example; pinned here as the ladder the anchors imply
   (components whole, right-aligned) — if a future oracle contradicts a row,
   that row is the one to revisit. */
data _null_;
  late  = '17:45:23't;     /* 63923 — 2-digit hour */
  early = '03:15:00't;     /* 11700 — single-digit hour: zero-pad costs a column */
  frac  = '17:45:23.125't; /* fractional seconds for the .d rows */
  wrap  = '26:15:00't;     /* 94500 — MOD note: wraps to 02:15:00 */
  put "[" late tod2.    "]";
  put "[" late tod3.    "]";
  put "[" late tod4.    "]";
  put "[" late tod5.    "]";
  put "[" late tod6.    "]";
  put "[" late tod7.    "]";
  put "[" late tod8.    "]";
  put "[" late tod9.    "]";
  put "[" late tod10.   "]";
  put "[" late tod10.2  "]";
  put "[" late tod11.2  "]";
  put "[" frac tod12.3  "]";
  put "[" late tod20.   "]";
  put "[" early tod4.   "]";
  put "[" early tod5.   "]";
  put "[" early tod7.   "]";
  put "[" early tod9.   "]";
  put "[" wrap tod8.    "]";
run;

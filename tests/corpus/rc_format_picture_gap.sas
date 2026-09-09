/* GAP-gapsexitingone §5b re-verdict — FILL= is a documented SAS 9.4
   PICTURE per-entry option (Procedures Guide 7th ed., printed
   pp. 1098-1099: 'The DATATYPE, DECSEP, DIG3SEP, FILL, LANGUAGE, MULT,
   NOEDIT, and PREFIX options are valid in parentheses after the
   user-supplied value label') opensas does not implement — an opensas
   gap, exit 2. Typo twin: rc_format_picture_typo.sas. expect-rc: 2 */
proc format;
  picture p low-high='99' (fill='*');
run;

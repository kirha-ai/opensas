/* BUG-pictureoverflowpanic (QA fuzz tick158): a PICTURE applied to a value
   whose scaled magnitude is >= 2^64 (~1.84e19) must NOT panic the interpreter
   (@intFromFloat overflow in renderPicture). Per SAS, a value that cannot fit
   the picture overflows the field to asterisks (like numeric formats that
   cannot represent the value). Fires on the default truncate path AND the
   (round) path; both are guarded. In-range values render unchanged. */
proc format;
  picture pb low-high='99999';
  picture pp low-high='00000' (prefix='$');
  picture pr low-high='009.9' (round);
run;
data _null_;
  huge = 1e20;
  put huge pb.;   /* overflow → asterisks, no panic */
  put huge pp.;   /* overflow → whole field (prefix+label) asterisks */
  put huge pr.;   /* overflow on the (round) path → asterisks */
  ok = 42;
  put ok pb.;     /* in-range control, zero-fill → 00042 */
  put ok pp.;     /* in-range control, suppression+prefix →    $42 */
run;

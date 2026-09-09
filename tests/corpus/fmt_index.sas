/* PERF-fmtscan: user formats resolved through the definition-time entry index.
   Exercises BOTH indexed paths (discrete numeric, discrete char) and the linear
   fallback (a true low-high range), plus OTHER/miss/no-OTHER cases. */
proc format;
  value visf 1="Screening" 2="Baseline" 3="Week 4" 4="Week 8" other="Unscheduled";
  value $armf "A"="Placebo" "B"="Active" other="Unknown";
  value gradef low-59="Fail" 60-79="Pass" 80-high="Distinction";
  value noother 1="one" 2="two";
run;
data _null_;
  /* discrete numeric (indexed) */
  do v = 1 to 5;
    s = put(v, visf.); put "vis_" v "=" s;
  end;
  /* discrete char (indexed), incl. miss->OTHER */
  a = put("A", armf.); put "arm_A=" a;
  a = put("B", armf.); put "arm_B=" a;
  a = put("Z", armf.); put "arm_Z=" a;
  /* numeric range (linear fallback) */
  do g = 55 to 85 by 10;
    r = put(g, gradef.); put "grade_" g "=" r;
  end;
  /* discrete numeric, no OTHER: unmatched renders raw */
  n = put(9, noother.); put "noother_9=" n;
  n = put(1, noother.); put "noother_1=" n;
  /* missing numeric under a format with OTHER -> OTHER */
  m = put(., visf.); put "vis_miss=" m;
run;

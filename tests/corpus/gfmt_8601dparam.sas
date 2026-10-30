/* BUG-8601dparam: E8601DT/E8601TM/B8601DT/B8601TM write formats honor
   documented .d fractional seconds (d 0-6). Extended forms use a decimal
   point; BASIC forms append packed fractional digits. E8601DZ also supports
   .d, with +00:00 and Z width rungs. Invented timestamp. */
data _null_;
  d = '15sep2018:14:52:22.125'dt;
  t = '14:52:22.125't;
  put "E25_3=" d e8601dt25.3 "|";
  put "E23_3=" d e8601dt23.3 "|";
  put "ET12_3=" t e8601tm12.3 "|";
  put "B22_3=" d b8601dt22.3 "|";
  put "BT10_3=" t b8601tm10.3 "|";
  put "DZ30_3=" d e8601dz30.3 "|";
  put "DZ26_3=" d e8601dz26.3 "|";
run;

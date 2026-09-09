proc format;
  value $sex "M"="Male" "F"="Female" other="Unknown";
  value ageg
    low - <18 = "Pediatric"
    18 - <65 = "Adult"
    65 - high = "Elderly";
  value $race "1"="WHITE" "2"="BLACK" "3"="ASIAN" other="OTHER";
run;
data dm;
  length subjid $4 sex $1 racecd $1;
  input subjid $ sex $ age racecd $;
  datalines;
S001 M 45 1
S002 F 8 2
S003 F 70 3
S004 X 30 9
;
run;
data _null_;
  set dm;
  sxd = put(sex, $sex.);
  agd = put(age, ageg.);
  rcd = put(racecd, $race.);
  put subjid "sex=" sxd "age=" agd "race=" rcd;
run;

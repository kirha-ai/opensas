/* GAP-8601b8601dndz: BASIC ISO DN/DZ read and write. DN formats a
   DATETIME's date part as yyyymmdd; DZ writes packed zero-meridian datetimes
   and reads packed +hhmm or Z offsets. Invented timestamp. */
data _null_;
  dt = '15sep2018:14:52:22'dt;
  frac = '15sep2018:14:52:22.123456'dt;
  put "DNDEF=" dt b8601dn. "|";
  put "DN8=" dt b8601dn8. "|";
  put "DZDEF=" dt b8601dz. "|";
  put "DZ20=" dt b8601dz20. "|";
  put "DZ22_3=" frac b8601dz22.3 "|";
  put "DZ23_3=" frac b8601dz23.3 "|";
  rdn = input("20180915", b8601dn8.);
  rdz = input("20180915T145222+0500", b8601dz20.);
  rzz = input("20180915T145222Z", b8601dz16.);
  put "RDN=" rdn e8601dt19. "|";
  put "RDZ=" rdz e8601dt19. "|";
  put "RZZ=" rzz e8601dt19. "|";
run;

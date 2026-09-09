/*=============================================================================
* Directory LIBNAME: `libname src "inputs"` points at a directory; the member
* `src.te` is auto-discovered as inputs/te.xpt and read via the XPORT engine
* (engine picked by extension). A fictional-study SDTM Trial-Elements table.
*============================================================================*/
libname src "inputs" access=readonly;
libname target "output";

data target.te;
  set src.te;
run;

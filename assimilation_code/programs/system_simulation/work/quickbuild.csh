#!/bin/csh
#
# DART software - Copyright UCAR. This open source software is provided
# by UCAR, "as is", without charge, subject to all terms of use at
# http://www.image.ucar.edu/DAReS/DART/DART_download
#
# DART $Id: quickbuild.csh 10982 2017-02-01 23:43:10Z thoar@ucar.edu $
#
# This script compiles all executables in this directory.

\rm -f *.o *.mod 

set MODEL = "system_simulation"

@ n = 0

#----------------------------------------------------------------------
# Build all the single-threaded targets
#----------------------------------------------------------------------

foreach TARGET ( mkmf_* )

   set PROG = `echo $TARGET | sed -e 's#mkmf_##'`

   @ n = $n + 1
   echo
   echo "---------------------------------------------------"
   echo "${MODEL} build number ${n} is ${PROG}" 
   \rm -f ${PROG}
   csh $TARGET || exit $n
   make        || exit $n

end

# clean up.  comment this out if you want to keep the .o and .mod files around
\rm -f *.o *.mod input.nml.*_default

echo "Success: All DART programs compiled."  

exit 0

# <next few lines under version control, do not edit>
# $URL: https://svn-dares-dart.cgd.ucar.edu/DART/releases/Manhattan/assimilation_code/programs/system_simulation/work/quickbuild.csh $
# $Revision: 10982 $
# $Date: 2017-02-01 18:43:10 -0500 (Wed, 01 Feb 2017) $


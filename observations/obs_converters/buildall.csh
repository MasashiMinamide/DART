#!/bin/csh
#
# DART software - Copyright UCAR. This open source software is provided
# by UCAR, "as is", without charge, subject to all terms of use at
# http://www.image.ucar.edu/DAReS/DART/DART_download
#
# DART $Id: buildall.csh 11317 2017-03-14 21:57:35Z nancy@ucar.edu $

set SNAME = $0
set clobber

set startdir=`pwd`

# the NCEP bufr libs are needed and they build differently.
# do them first.

cd NCEP/prep_bufr

echo 
echo 
echo "=================================================================="
echo "=================================================================="
echo "Compiling NCEP BUFR libs starting at "`date`
echo "=================================================================="
echo "=================================================================="
echo 
echo 

./install.sh

echo 
echo 
echo "=================================================================="
echo "=================================================================="
echo "Build of NCEP BUFR libs ended at "`date`
echo "=================================================================="
echo "=================================================================="
echo 
echo 

cd $startdir

foreach project ( `find . -name quickbuild.csh -print` )

   cd $startdir

   set dir = $project:h
   set FAILURE = 0

   echo 
   echo 
   echo "=================================================================="
   echo "=================================================================="
   echo "Compiling obs converter $dir starting at "`date`
   echo "=================================================================="
   echo "=================================================================="
   echo 
   echo 


   cd $dir
   echo
   echo building in $dir

   ./quickbuild.csh || set FAILURE = 1

   echo
   echo
   echo "=================================================================="
   echo "=================================================================="

   if ( $FAILURE ) then
      echo "ERROR - unsuccessful build in $dir at "`date`
      echo 

      switch ( $dir )
   
         case */var/*
            echo "This build expected to fail unless you have the WRF code in-situ."
         breaksw
            
         case *AIRS*
            echo "AIRS build is expected to fail due to dependency on hdfeos libs,"
            echo "not required to be part of the standard DART environment."
         breaksw
            
         case *quikscat*
            echo "quikscat build is expected to fail due to dependency on mfhdf libs,"
            echo "not required to be part of the standard DART environment."
         breaksw
  
         default
            echo " unexpected error"
         breaksw
      endsw
   else
      echo "Successful build of obs converter $dir ended at "`date`
   endif

   echo "=================================================================="
   echo "=================================================================="
   echo
   echo
  
end

exit 0

# <next few lines under version control, do not edit>
# $URL: https://svn-dares-dart.cgd.ucar.edu/DART/releases/Manhattan/observations/obs_converters/buildall.csh $
# $Revision: 11317 $
# $Date: 2017-03-14 17:57:35 -0400 (Tue, 14 Mar 2017) $


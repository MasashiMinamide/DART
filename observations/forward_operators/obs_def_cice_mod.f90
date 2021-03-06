! DART software - Copyright UCAR. This open source software is provided
! by UCAR, "as is", without charge, subject to all terms of use at
! http://www.image.ucar.edu/DAReS/DART/DART_download
!
! $Id: obs_def_cice_mod.f90 11289 2017-03-10 21:56:06Z hendric@ucar.edu $

! FIXME: check to see if obs are of volume or thickness - for now we
! will assume volume.

! FIXME: do we want to identify the satellite? (yes)
!  AMSRE is a passive microwave

! BEGIN DART PREPROCESS KIND LIST
!SAT_SEAICE_AGREG_CONCENTR,       QTY_SEAICE_AGREG_CONCENTR,     COMMON_CODE
!SYN_SEAICE_CONCENTR,             QTY_SEAICE_CONCENTR,           COMMON_CODE
!SAT_SEAICE_AGREG_VOLUME,         QTY_SEAICE_AGREG_VOLUME,       COMMON_CODE
!SAT_SEAICE_AGREG_SNOWVOLUME,     QTY_SEAICE_AGREG_SNOWVOLUME,   COMMON_CODE
!SAT_SEAICE_AGREG_THICKNESS,      QTY_SEAICE_AGREG_THICKNESS,    COMMON_CODE
!SAT_SEAICE_AGREG_SNOWDEPTH,      QTY_SEAICE_AGREG_SNOWDEPTH,    COMMON_CODE
!SAT_U_SEAICE_COMPONENT,          QTY_U_SEAICE_COMPONENT,        COMMON_CODE
!SAT_V_SEAICE_COMPONENT,          QTY_V_SEAICE_COMPONENT,        COMMON_CODE
!SAT_SEAICE_CONCENTR,             QTY_SEAICE_CONCENTR,           COMMON_CODE
!SAT_SEAICE_VOLUME,               QTY_SEAICE_VOLUME,             COMMON_CODE
!SAT_SEAICE_SNOWVOLUME,           QTY_SEAICE_SNOWVOLUME,         COMMON_CODE
!SAT_SEAICE_AGREG_FY,             QTY_SEAICE_AGREG_FY,           COMMON_CODE
! END DART PREPROCESS KIND LIST

! <next few lines under version control, do not edit>
! $URL: https://svn-dares-dart.cgd.ucar.edu/DART/releases/Manhattan/observations/forward_operators/obs_def_cice_mod.f90 $
! $Id: obs_def_cice_mod.f90 11289 2017-03-10 21:56:06Z hendric@ucar.edu $
! $Revision: 11289 $
! $Date: 2017-03-10 16:56:06 -0500 (Fri, 10 Mar 2017) $

#!/bin/bash

#
#-----------------------------------------------------------------------
#
# Source the variable definitions file and the bash utility functions.
#
#-----------------------------------------------------------------------
#
. ${GLOBAL_VAR_DEFNS_FP}
. $USHDIR/source_util_funcs.sh
#
#-----------------------------------------------------------------------
#
# Save current shell options (in a global array).  Then set new options
# for this script/function.
#
#-----------------------------------------------------------------------
#
{ save_shell_opts; set -u +x; } > /dev/null 2>&1
#
#-----------------------------------------------------------------------
#
# Get the full path to the file in which this script/function is located 
# (scrfunc_fp), the name of that file (scrfunc_fn), and the directory in
# which the file is located (scrfunc_dir).
#
#-----------------------------------------------------------------------
#
scrfunc_fp=$( readlink -f "${BASH_SOURCE[0]}" )
scrfunc_fn=$( basename "${scrfunc_fp}" )
scrfunc_dir=$( dirname "${scrfunc_fp}" )
#
#-----------------------------------------------------------------------
#
# Print message indicating entry into script.
#
#-----------------------------------------------------------------------
#
print_info_msg "
========================================================================
Entering script:  \"${scrfunc_fn}\"
In directory:     \"${scrfunc_dir}\"

This is the ex-script for the task that generates lateral boundary con-
dition (LBC) files (in NetCDF format) for all LBC update hours (except 
hour zero). 
========================================================================"
#
#-----------------------------------------------------------------------
#
# Specify the set of valid argument names for this script/function.  
# Then process the arguments provided to this script/function (which 
# should consist of a set of name-value pairs of the form arg1="value1",
# etc).
#
#-----------------------------------------------------------------------
#
valid_args=( \
"EXTRN_MDL_FNS" \
"EXTRN_MDL_FILES_DIR" \
"EXTRN_MDL_CDATE" \
"WGRIB2_DIR" \
"APRUN" \
"LBCS_DIR" \
"EXTRN_MDL_LBC_UPDATE_FHRS" \
)
process_args valid_args "$@"
#
#-----------------------------------------------------------------------
#
# For debugging purposes, print out values of arguments passed to this
# script.  Note that these will be printed out only if VERBOSE is set to
# TRUE.
#
#-----------------------------------------------------------------------
#
print_input_args valid_args
#
#-----------------------------------------------------------------------
#
#
#
#-----------------------------------------------------------------------
#
workdir="${LBCS_DIR}/tmp_LBCS"
mkdir_vrfy -p "$workdir"
cd_vrfy $workdir
#
#-----------------------------------------------------------------------
#
# Set physics-suite-dependent variables that are needed in the FORTRAN
# namelist file that the chgres executable will read in.
#
#-----------------------------------------------------------------------
#
phys_suite=""

case "${CCPP_PHYS_SUITE}" in

"FV3_GFS_2017_gfdlmp")
  phys_suite="GFS"
  ;;

"FV3_GSD_v0" | "FV3_GSD_SAR" | "FV3_GSD_SAR_v1")
  phys_suite="GSD"
  ;;
"FV3_CPT_v0" )
  phys_suite="CPT"
  ;;
"FV3_GFS_v15p2" )
  phys_suite="v15p2"
  ;;
"FV3_GFS_v16beta" )
  phys_suite="v16beta"
  ;;

*)
  print_err_msg_exit "\
Physics-suite-dependent namelist variables have not yet been specified 
for this physics suite:
  CCPP_PHYS_SUITE = \"${CCPP_PHYS_SUITE}\""
  ;;

esac
#
#-----------------------------------------------------------------------
#
# Set external-model-dependent variables that are needed in the FORTRAN
# namelist file that the chgres executable will read in.  These are de-
# scribed below.  Note that for a given external model, usually only a
# subset of these all variables are set (since some may be irrelevant).
#
# external_model:
# Name of the external model from which we are obtaining the fields 
# needed to generate the ICs.
#
# fn_sfc_nemsio:
# Name (not including path) of the nemsio file generated by the external
# model that contains the surface fields.
#
# input_type:
# The "type" of input being provided to chgres.  This contains a combi-
# nation of information on the external model, external model file for-
# mat, and maybe other parameters.  For clarity, it would be best to 
# eliminate this variable in chgres and replace with with 2 or 3 others
# (e.g. extrn_mdl, extrn_mdl_file_format, etc).
# 
# tracers_input:
# List of atmospheric tracers to read in from the external model file
# containing these tracers.
#
# tracers:
# Names to use in the output NetCDF file for the atmospheric tracers 
# specified in tracers_input.  With the possible exception of GSD phys-
# ics, the elements of this array should have a one-to-one correspond-
# ence with the elements in tracers_input, e.g. if the third element of
# tracers_input is the name of the O3 mixing ratio, then the third ele-
# ment of tracers should be the name to use for the O3 mixing ratio in
# the output file.  For GSD physics, three additional tracers -- ice, 
# rain, and water number concentrations -- may be specified at the end
# of tracers, and these will be calculated by chgres.
#
# numsoil_out:
# The number of soil layers to include in the output NetCDF file.
#
# replace_FIELD, where FIELD="vgtyp", "sotyp", or "vgfrc":
# Logical variable indicating whether or not to obtain the field in 
# question from climatology instead of the external model.  The field in
# question is one of vegetation type (FIELD="vgtyp"), soil type (FIELD=
# "sotyp"), and vegetation fraction (FIELD="vgfrc").  If replace_FIELD
# is set to ".true.", then the field is obtained from climatology (re-
# gardless of whether or not it exists in an external model file).  If
# it is set to ".false.", then the field is obtained from the external 
# model.  If the external model file does not provide this field, then
# chgres prints out an error message and stops.
#
# tg3_from_soil:
# Logical variable indicating whether or not to set the tg3 soil tempe-  # Needs to be verified.
# rature field to the temperature of the deepest soil layer. 
#
#-----------------------------------------------------------------------
#

# GSK comments about chgres:
#
# The following are the three atmsopheric tracers that are in the atmo-
# spheric analysis (atmanl) nemsio file for CDATE=2017100700:
#
#   "spfh","o3mr","clwmr"
#
# Note also that these are hardcoded in the code (file input_data.F90, 
# subroutine read_input_atm_gfs_spectral_file), so that subroutine will
# break if tracers_input(:) is not specified as above.
#
# Note that there are other fields too ["hgt" (surface height (togography?)), 
# pres (surface pressure), ugrd, vgrd, and tmp (temperature)] in the atmanl file, but those
# are not considered tracers (they're categorized as dynamics variables,
# I guess).
#
# Another note:  The way things are set up now, tracers_input(:) and 
# tracers(:) are assumed to have the same number of elements (just the
# atmospheric tracer names in the input and output files may be differ-
# ent).  There needs to be a check for this in the chgres_cube code!!
# If there was a varmap table that specifies how to handle missing 
# fields, that would solve this problem.
#
# Also, it seems like the order of tracers in tracers_input(:) and 
# tracers(:) must match, e.g. if ozone mixing ratio is 3rd in 
# tracers_input(:), it must also be 3rd in tracers(:).  How can this be checked?
#
# NOTE: Really should use a varmap table for GFS, just like we do for 
# RAP/HRRR.
#

# A non-prognostic variable that appears in the field_table for GSD physics 
# is cld_amt.  Why is that in the field_table at all (since it is a non-
# prognostic field), and how should we handle it here??

# I guess this works for FV3GFS but not for the spectral GFS since these
# variables won't exist in the spectral GFS atmanl files.
#  tracers_input="\"sphum\",\"liq_wat\",\"ice_wat\",\"rainwat\",\"snowwat\",\"graupel\",\"o3mr\""
#
# Not sure if tracers(:) should include "cld_amt" since that is also in
# the field_table for CDATE=2017100700 but is a non-prognostic variable.

external_model=""
fn_atm_nemsio=""
fn_sfc_nemsio=""
fn_grib2=""
input_type=""
tracers_input="\"\""
tracers="\"\""
numsoil_out=""
geogrid_file_input_grid=""
replace_vgtyp=""
replace_sotyp=""
replace_vgfrc=""
tg3_from_soil=""


case "${EXTRN_MDL_NAME_LBCS}" in


"GSMGFS")

  external_model="GSMGFS"

  input_type="gfs_gaussian" # For spectral GFS Gaussian grid in nemsio format.

  tracers_input="\"spfh\",\"clwmr\",\"o3mr\""
  tracers="\"sphum\",\"liq_wat\",\"o3mr\""

  numsoil_out="4"
  replace_vgtyp=".true."
  replace_sotyp=".true."
  replace_vgfrc=".true."
  tg3_from_soil=".false."

  ;;


"FV3GFS")

  if [ "${FV3GFS_FILE_FMT_LBCS}" = "nemsio" ]; then

    external_model="FV3GFS"

    input_type="gaussian"     # For FV3-GFS Gaussian grid in nemsio format.

    tracers_input="\"spfh\",\"clwmr\",\"o3mr\",\"icmr\",\"rwmr\",\"snmr\",\"grle\""
#
# If CCPP is being used, then the list of atmospheric tracers to include
# in the output file depends on the physics suite.  Hopefully, this me-
# thod of specifying output tracers will be replaced with a variable 
# table (which should be specific to each combination of external model,
# external model file type, and physics suite).
#
    if [ "${USE_CCPP}" = "TRUE" ]; then
      if [ "${CCPP_PHYS_SUITE}" = "FV3_GFS_2017_gfdlmp" ] || \
         [ "${CCPP_PHYS_SUITE}" = "FV3_CPT_v0" ] || \
         [ "${CCPP_PHYS_SUITE}" = "FV3_GFS_v15p2" ] || \
         [ "${CCPP_PHYS_SUITE}" = "FV3_GFS_v16beta" ]; then
        tracers="\"sphum\",\"liq_wat\",\"o3mr\",\"ice_wat\",\"rainwat\",\"snowwat\",\"graupel\""
      elif [ "${CCPP_PHYS_SUITE}" = "FV3_GSD_v0" ] || \
           [ "${CCPP_PHYS_SUITE}" = "FV3_GSD_SAR_v1" ] || \
           [ "${CCPP_PHYS_SUITE}" = "FV3_GSD_SAR" ]; then
# For GSD physics, add three additional tracers (the ice, rain and water
# number concentrations) that are required for Thompson microphysics.
        tracers="\"sphum\",\"liq_wat\",\"o3mr\",\"ice_wat\",\"rainwat\",\"snowwat\",\"graupel\",\"ice_nc\",\"rain_nc\",\"water_nc\""
      fi
#
# If CCPP is not being used, the only physics suite that can be used is
# GFS.
#
    else
      tracers="\"sphum\",\"liq_wat\",\"o3mr\",\"ice_wat\",\"rainwat\",\"snowwat\",\"graupel\""
    fi

  elif [ "${FV3GFS_FILE_FMT_LBCS}" = "grib2" ]; then

    external_model="GFS"

    input_type="grib2"
    fn_grib2="${EXTRN_MDL_FNS[0]}"

  fi

  numsoil_out="4"
  replace_vgtyp=".true."
  replace_sotyp=".true."
  replace_vgfrc=".true."
  tg3_from_soil=".false."

  ;;


"RAPX")

  external_model="RAP"

  input_type="grib2"

  if [ "${USE_CCPP}" = "TRUE" ]; then
    if [ "${CCPP_PHYS_SUITE}" = "FV3_GFS_2017_gfdlmp" ] || \
       [ "${CCPP_PHYS_SUITE}" = "FV3_CPT_v0" ] || \
       [ "${CCPP_PHYS_SUITE}" = "FV3_GSD_SAR_v1" ] || \
       [ "${CCPP_PHYS_SUITE}" = "FV3_GFS_v15p2" ] || \
       [ "${CCPP_PHYS_SUITE}" = "FV3_GFS_v16beta" ]; then
      numsoil_out="4"
    elif [ "${CCPP_PHYS_SUITE}" = "FV3_GSD_v0" ] || \
         [ "${CCPP_PHYS_SUITE}" = "FV3_GSD_SAR" ]; then
      numsoil_out="9"
    fi
  fi

  replace_vgtyp=".false."
  replace_sotyp=".false."
  replace_vgfrc=".false."
  tg3_from_soil=".true."

  ;;


*)
  print_err_msg_exit "\
External-model-dependent namelist variables have not yet been specified 
for this external model:
  EXTRN_MDL_NAME_LBCS = \"${EXTRN_MDL_NAME_LBCS}\""
  ;;


esac
#
#-----------------------------------------------------------------------
#
# Loop through the LBC update times and run chgres for each such time to
# obtain an LBC file for each that can be used as input to the FV3SAR.
#
#-----------------------------------------------------------------------
#
num_fhrs="${#EXTRN_MDL_LBC_UPDATE_FHRS[@]}"
for (( i=0; i<${num_fhrs}; i++ )); do
#
# Get the forecast hour of the external model.
#
  fhr="${EXTRN_MDL_LBC_UPDATE_FHRS[$i]}"
#
# Set external model output file name and file type/format.  Note that
# these are now inputs into chgres.
#
  fn_atm_nemsio=""
  fn_grib2=""

  case "${EXTRN_MDL_NAME_LBCS}" in
  "GSMGFS")
    fn_atm_nemsio="${EXTRN_MDL_FNS[$i]}"
    ;;
  "FV3GFS")
     if [ "${FV3GFS_FILE_FMT_LBCS}" = "nemsio" ]; then
       fn_atm_nemsio="${EXTRN_MDL_FNS[$i]}"
     elif [ "${FV3GFS_FILE_FMT_LBCS}" = "grib2" ]; then
       fn_grib2="${EXTRN_MDL_FNS[$i]}"
     fi
    ;;
  "RAPX")
    fn_grib2="${EXTRN_MDL_FNS[$i]}"
    ;;
  *)
    print_err_msg_exit "\
The external model output file name to use in the chgres FORTRAN name-
list file has not specified for this external model:
  EXTRN_MDL_NAME_LBCS = \"${EXTRN_MDL_NAME_LBCS}\""
    ;;
  esac
#
# Get the starting year, month, day, and hour of the the external model
# run.  Then add the forecast hour to it to get a date and time corres-
# ponding to the current forecast time.
#
#  yyyy="${EXTRN_MDL_CDATE:0:4}"
  mm="${EXTRN_MDL_CDATE:4:2}"
  dd="${EXTRN_MDL_CDATE:6:2}"
  hh="${EXTRN_MDL_CDATE:8:2}"
  yyyymmdd="${EXTRN_MDL_CDATE:0:8}"

  cdate_crnt_fhr=$( date --utc --date "${yyyymmdd} ${hh} UTC + ${fhr} hours" "+%Y%m%d%H" )
#
# Get the year, month, day, and hour corresponding to the current fore-
# cast time of the the external model.
#
#  yyyy="${cdate_crnt_fhr:0:4}"
  mm="${cdate_crnt_fhr:4:2}"
  dd="${cdate_crnt_fhr:6:2}"
  hh="${cdate_crnt_fhr:8:2}"
#
# Build the FORTRAN namelist file that chgres_cube will read in.
#
# QUESTION:
# Do numsoil_out, ..., tg3_from_soil need to be in this namelist (as 
# they are for the ICs namelist)?
  { cat > fort.41 <<EOF
&config
 fix_dir_target_grid="${FIXsar}"
 mosaic_file_target_grid="${FIXsar}/${CRES}${DOT_OR_USCORE}mosaic.halo${NH4}.nc"
 orog_dir_target_grid="${FIXsar}"
 orog_files_target_grid="${CRES}${DOT_OR_USCORE}oro_data.tile7.halo${NH4}.nc"
 vcoord_file_target_grid="${FIXam}/global_hyblev.l65.txt"
 mosaic_file_input_grid=""
 orog_dir_input_grid=""
 base_install_dir="${CHGRES_DIR}"
 wgrib2_path="${WGRIB2_DIR}"
 data_dir_input_grid="${EXTRN_MDL_FILES_DIR}"
 atm_files_input_grid="${fn_atm_nemsio}"
 sfc_files_input_grid="${fn_sfc_nemsio}"
 grib2_file_input_grid="${fn_grib2}"
 cycle_mon=${mm}
 cycle_day=${dd}
 cycle_hour=${hh}
 convert_atm=.true.
 convert_sfc=.false.
 convert_nst=.false.
 regional=2
 halo_bndy=${NH4}
 input_type="${input_type}"
 external_model="${external_model}"
 tracers_input=${tracers_input}
 tracers=${tracers}
 phys_suite="${phys_suite}"
/
EOF
  } || print_err_msg_exit "\
\"cat\" command to create a namelist file for chgres_cube to generate LBCs
for all boundary update times (except the 0-th forecast hour) returned 
with nonzero status."
#
# Run chgres_cube.
#
  ${APRUN} ${EXECDIR}/chgres_cube.exe || \
  print_err_msg_exit "\
Call to executable to generate lateral boundary conditions file for the
the FV3SAR failed:
  EXTRN_MDL_NAME_LBCS = \"${EXTRN_MDL_NAME_LBCS}\"
  EXTRN_MDL_FILES_DIR = \"${EXTRN_MDL_FILES_DIR}\"
  fhr = \"$fhr\""
#
# Move LBCs file for the current lateral boundary update time to the ICs
# /LBCs work directory.  Note that we rename the file using the forecast
# hour of the FV3SAR (which is not necessarily the same as that of the 
# external model since their start times may be offset).
#
  fcst_hhh_FV3SAR=$( printf "%03d" "${LBC_UPDATE_FCST_HRS[$i]}" )
  mv_vrfy gfs_bndy.nc ${LBCS_DIR}/gfs_bndy.tile7.${fcst_hhh_FV3SAR}.nc

done
#
#-----------------------------------------------------------------------
#
# Print message indicating successful completion of script.
#
#-----------------------------------------------------------------------
#
print_info_msg "
========================================================================
Lateral boundary condition (LBC) files (in NetCDF format) generated suc-
cessfully for all LBC update hours (except hour zero)!!!

Exiting script:  \"${scrfunc_fn}\"
In directory:    \"${scrfunc_dir}\"
========================================================================"
#
#-----------------------------------------------------------------------
#
# Restore the shell options saved at the beginning of this script/func-
# tion.
#
#-----------------------------------------------------------------------
#
{ restore_shell_opts; } > /dev/null 2>&1

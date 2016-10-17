## Includes PrepSubject.mk, PreprocessSubjects.mk and feat.mk

cwd = $(shell pwd)
# The subject variable is set here and is available to recipes, targets, etc.
SUBJECT=$(notdir $(cwd))

# Set open MP number of threads to be 1, so that we can parallelize using make.
export OMP_NUM_THREADS=1

#Print out variable
print-%  : ; @echo $* = $($*)

SHELL=/bin/bash
PROJECT_DIR=/mnt/stressdevlab/new_memory_pipeline/DTI
STANDARD_DIR=$(PROJECT_DIR)/Standard
SUBJECTS_DIR=$(PROJECT_DIR)/final_FreeSurfer
FSL_DIR=/usr/share/fsl/5.0
AFNIpath=/usr/bin/afni
ANTSpath=/usr/local/ANTs-2.1.0-rc3/bin/
SubjDir=$(PROJECT_DIR)/$(SUBJECT)
SCRIPTpath=$(PROJECT_DIR)/bin
TEMPLATES=$(PROJECT_DIR)/templates
RScripts= $(SCRIPTpath)/QA_RScripts

include ./newdti.mk

#subject: PrepSubject PreprocessSubject feat PPI ROI

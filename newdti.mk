
# This makefile runs through the DTI preprocessing pipeline

cwd = $(shell pwd)
OUTDIR=out

SDC_METHOD = $(shell if [ -f fieldmap_phase.nii.gz ] ; then echo FUGUE; \
                    elif [ -f acqparams.txt ] ; then echo TOPUP; \
                    else echo FALSE ; fi)

# Set open MP number of threads to be 1, so that we can parallelize using make.
export OMP_NUM_THREADS=1

.PHONY: Convert BrainMasks Eddy FitTensor DTIQA RegMasks RegDTI

# keep everything by default
.SECONDARY:

define dti_usage
	@echo
	@echo
	@echo Usage:
	@echo "make tensor		Makes the fa and tensor images"
	@echo "make clean		Removes everything except for the source data"
	@echo "make mostlyclean		Removes intermediate files"
	@echo
	@echo
endef

Convert: fieldmap/B0.nii.gz dti/DTI64.nii.gz
BrainMasks: dti/S0.nii.gz memprage/T1_optiBET_brain_mask_dilx2.nii.gz memprage/T1_brain_masked_dilx2.nii.gz xfm_dir/T1_brain_mask_to_S0_a_dilx2_Warped.nii.gz xfm_dir/T1_brain_mask_to_S0_r_dilx2_Warped.nii.gz dti/brainmask.nii.gz dti/brainmask_dilx2.nii.gz
Eddy: dti/acqparams.txt dti/mc_dti/mc_DTI64.nii.gz
FitTensor: dti/dtifit/dti_FA.nii.gz
DTIQA: QA/DTI64_QASummary.txt QA/QA_Metrics.txt
TestMasks: $(patsubst %,memprage/T1_optiBET_brain_mask_dilx%.nii.gz, 0 1 2 3) $(patsubst %,xfm_dir/T1_brain_mask_to_FA_r_dilx%_Warped.nii.gz, 0 1 2 3)
RegMasks: dti/dtifit/dti_FA_brain.nii.gz xfm_dir/dti_FA_brain_to_MNI_r_Warped.nii.gz
RegDTI: xfm_dir/dti_FA_to_MNI_Warped.nii.gz
PreprocessSubject: Convert BrainMasks Eddy FitTensor DTIQA RegMasks RegDTI


## 1. Convert PAR/RECs to NIFTI
fieldmap/B0.nii.gz: ${SubjDir}/parrecs/B0.PAR ${SubjDir}/parrecs/B0.REC
	parrec2nii -c -b -i -d --field-strength=3 --strict-sort --keep-trace --store-header -o $(SubjDir)/fieldmap $(SubjDir)/parrecs/B0.PAR

dti/DTI64.nii.gz: ${SubjDir}/parrecs/DTI64.PAR ${SubjDir}/parrecs/DTI64.REC
	parrec2nii -c -b -i -d --field-strength=3 --strict-sort --keep-trace --store-header -o $(SubjDir)/dti $(SubjDir)/parrecs/DTI64.PAR

## 2. Make S0 image and fake mask (to avoid skull-stripping until after dtifit)
dti/S0.nii.gz: dti/DTI64.nii.gz
	fslroi $(word 1,$^) $@ 0 1 ;\

memprage/T1_optiBET_brain_mask_dilx2.nii.gz: memprage/T1_optiBET_brain_mask.nii.gz
	fslmaths $(word 1,$^) -dilM -dilM -bin $@ ;\

memprage/T1_brain_masked_dilx2.nii.gz: memprage/T1_optiBET_brain_mask_dilx2.nii.gz memprage/T1.nii.gz
	fslmaths $(word 2,$^) -mas $(word 1,$^) $@

xfm_dir/T1_brain_mask_to_S0_r_dilx2_Warped.nii.gz: memprage/T1_brain_masked_dilx2.nii.gz dti/S0.nii.gz
	SGE_RREQ="-q global.q" antsRegistrationSyN.sh -d 3 -t r -f dti/S0.nii.gz -m memprage/T1_brain_masked_dilx2.nii.gz -o xfm_dir/T1_brain_mask_to_S0_r_dilx2_ ;\

xfm_dir/T1_brain_mask_to_S0_a_dilx2_Warped.nii.gz: memprage/T1_brain_masked_dilx2.nii.gz dti/S0.nii.gz
	SGE_RREQ="-q global.q" antsRegistrationSyN.sh -d 3 -t a -f dti/S0.nii.gz -m memprage/T1_brain_masked_dilx2.nii.gz -o xfm_dir/T1_brain_mask_to_S0_a_dilx2_ ;\

dti/brainmask.nii.gz: xfm_dir/T1_brain_mask_to_S0_a_dilx2_Warped.nii.gz
	fslmaths $(word 1,$^) -bin $@ ;\

dti/brainmask_dilx2.nii.gz: dti/brainmask.nii.gz
	fslmaths $(word 1,$^) -dilM -dilM $@ ;\

## 3. Do motion correction with eddy
dti/acqparams.txt: dti/DTI64.nii.gz
	dwell_time=`cat dti/DTI64.dwell_time` ;\
	echo "1 0 0 $${dwell_time}" > $@ ;\

dti/mc_dti/mc_DTI64.nii.gz: dti/DTI64.nii.gz dti/brainmask.nii.gz dti/acqparams.txt
	mkdir -p `dirname $@` ;\
	SGE_RREQ="-q global.q" bash /mnt/stressdevlab/scripts/DTI/dti_preproc/motion_correct.sh -a $(SubjDir)/dti/acqparams.txt -k $(SubjDir)/dti/DTI64.nii.gz -b $(SubjDir)/dti/DTI64.bvals -r $(SubjDir)/dti/DTI64.bvecs -M dti/brainmask.nii.gz -o $(SubjDir)/`dirname $@` -p $(SubjDir)/parrecs/DTI64.PAR ;\


## 4. Fit tensors with dtifit
dti/dtifit/dti_FA.nii.gz: dti/mc_dti/mc_DTI64.nii.gz dti/brainmask.nii.gz
	/mnt/stressdevlab/scripts/DTI/dti_preproc/ols_fit_tensor.sh -k $(word 1,$^) -b dti/DTI64.bvals -r dti/mc_dti/bvec_mc.txt -M dti/brainmask.nii.gz -o $(SubjDir)/`dirname $@` -f ;\


## 5. Brain mask


dti/mc_dti/mc_DTI64_S0.nii.gz: dti/mc_dti/mc_DTI64.nii.gz
	fslroi $(word 1,$^) $@ 0 1 ;\


#This is important for template creation!
xfm_dir/dti_FA_to_MNI_1mm_r_Warped.nii.gz: dti/dtifit/dti_FA.nii.gz
	SGE_RREQ="-q global.q" antsRegistrationSyN.sh -d 3 -t r -f /usr/share/fsl/data/standard/MNI152_T1_1mm_brain.nii.gz -m dti/dtifit/dti_FA.nii.gz -o xfm_dir/dti_FA_to_MNI_1mm_r_ ;\

## 5. Do QA
QA/dtiprep/dwi_fixed_QCReport.txt: dti/DTI64.nii.gz
	bash /mnt/stressdevlab/new_memory_pipeline/DTI/ConvertNRRD_DTIPrep.sh $(SUBJECT)

QA/DTI64_QASummary.txt: dti/mc_dti/mc_DTI64.nii.gz dti/DTI64.bvals dti/mc_dti/bvec_mc.txt dti/brainmask.nii.gz
	sed -e 's|\.0||g' $(word 2,$^) > dti/DTI64.bvals.new ;\
	/mnt/stressdevlab/scripts/DTI/QA/qa_dti1.sh $(SubjDir)/$(word 1,$^) $(SubjDir)/dti/DTI64.bvals.new $(SubjDir)/$(word 3,$^) $(SubjDir)/$(word 4,$^) $@ ;\

QA/slicecorr.png: dti/mc_dti/mc_DTI64.nii.gz dti/DTI64.bvals
	python /mnt/stressdevlab/scripts/DTI/QA/dtiprep.py -f $(SubjDir)/dti/DTI64.nii.gz

QA/QA_Metrics.txt: QA/DTI64_QASummary.txt dti/mc_dti/mc_DTI64.nii.gz
	bash /mnt/stressdevlab/scripts/DTI/QA/ParseQAReport.sh $(SUBJECT)

## 6. Register to MNI space
xfm_dir/dti_FA_to_MNI_Warped.nii.gz: dti/dtifit/dti_FA.nii.gz
	antsRegistrationSyN.sh -d 3 -f /usr/share/fsl/data/standard/MNI152_T1_2mm_brain.nii.gz -m $(word 1,$^) -t r -o xfm_dir/dti_FA_to_MNI_

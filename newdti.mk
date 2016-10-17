
# This makefile runs through the DTI preprocessing pipleline
# Warning: non-standard configuration as below:
# 1. Left-Right phase encoding direction
# 2. Skull-stripping after tensor fit
# 3. Very dilated (2x) brain mask (due to Left-Right phase encoding direction issue)

cwd = $(shell pwd)
OUTDIR=out

SDC_METHOD = $(shell if [ -f fieldmap_phase.nii.gz ] ; then echo FUGUE; \
                    elif [ -f acqparams.txt ] ; then echo TOPUP; \
                    else echo FALSE ; fi)

# Set open MP number of threads to be 1, so that we can parallelize using make.
export OMP_NUM_THREADS=1

.PHONY: Convert BrainMasks Eddy FitTensor DTIQA TestMasks RegMasks RegDTI

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
BrainMasks: dti/S0.nii.gz dti/S0_fake_mask.nii.gz
Eddy: dti/acqparams.txt dti/mc_dti/mc_DTI64.nii.gz
FitTensor: dti/dtifit/dti_FA.nii.gz
DTIQA: QA/DTI64_QASummary.txt QA/QA_Metrics.txt
TestMasks: $(patsubst %,memprage/T1_optiBET_brain_mask_dilx%.nii.gz, 0 1 2 3) $(patsubst %,xfm_dir/T1_brain_mask_to_FA_r_dilx%_Warped.nii.gz, 0 1 2 3)
RegMasks: dti/brainmask.nii.gz dti/dtifit/dti_FA_brain.nii.gz xfm_dir/dti_FA_brain_to_MNI_r_Warped.nii.gz
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

dti/S0_fake_mask.nii.gz: dti/S0.nii.gz
	cp $(word 1,$^) $@ ;\


## 3. Do motion correction with eddy
dti/acqparams.txt: dti/DTI64.nii.gz
	dwell_time=`cat dti/DTI64.dwell_time` ;\
	echo "1 0 0 $${dwell_time}" > $@ ;\

dti/mc_dti/mc_DTI64.nii.gz: dti/DTI64.nii.gz dti/S0_fake_mask.nii.gz dti/acqparams.txt
		mkdir -p `dirname $@` ;\
		bash /mnt/stressdevlab/scripts/DTI/dti_preproc/motion_correct.sh -a $(SubjDir)/dti/acqparams.txt -k $(SubjDir)/dti/DTI64.nii.gz -b $(SubjDir)/dti/DTI64.bvals -r $(SubjDir)/dti/DTI64.bvecs -M $(SubjDir)/dti/S0_fake_mask.nii.gz -o $(SubjDir)/`dirname $@` ;\

## 4. Fit tensors with dtifit
dti/dtifit/dti_FA.nii.gz: dti/mc_dti/mc_DTI64.nii.gz
		/mnt/stressdevlab/scripts/DTI/dti_preproc/ols_fit_tensor.sh -k $(word 1,$^) -b dti/DTI64.bvals -r dti/mc_dti/bvec_mc.txt -M dti/S0_fake_mask.nii.gz -o $(SubjDir)/`dirname $@` -f ;\

## 5. Brain mask

xfm_dir/T1_brain_mask_to_FA_r_dilx%_Warped.nii.gz: dti/dtifit/dti_FA.nii.gz memprage/T1_optiBET_brain_mask_dilx%.nii.gz
	dilval=$* ;\
	antsRegistrationSyN.sh -d 3 -t r -f dti/dtifit/dti_FA.nii.gz -m $(word 2,$^) -o xfm_dir/T1_brain_mask_to_FA_r_dilx$${dilval}_ ;\

memprage/T1_optiBET_brain_mask_dilx0.nii.gz: memprage/T1_optiBET_brain_mask.nii.gz
	fslmaths $(word 1,$^) -bin $@ ;\

memprage/T1_optiBET_brain_mask_dilx1.nii.gz: memprage/T1_optiBET_brain_mask.nii.gz
	fslmaths $(word 1,$^) -dilM -bin $@ ;\

memprage/T1_optiBET_brain_mask_dilx2.nii.gz: memprage/T1_optiBET_brain_mask.nii.gz
	fslmaths $(word 1,$^) -dilM -dilM -bin $@ ;\

memprage/T1_optiBET_brain_mask_dilx3.nii.gz: memprage/T1_optiBET_brain_mask.nii.gz
	fslmaths $(word 1,$^) -dilM -dilM -dilM -bin $@ ;\

memprage/T1_brain_masked_dilx%.nii.gz: memprage/T1_optiBET_brain_mask_dilx%.nii.gz memprage/T1.nii.gz
	fslmaths $(word 2,$^) -mas $(word 1,$^) $@

dti/mc_dti/mc_DTI64_S0.nii.gz: dti/mc_dti/mc_DTI64.nii.gz
	fslroi $(word 1,$^) $@ 0 1 ;\

dti/brainmask.nii.gz: xfm_dir/T1_brain_mask_to_FA_r_dilx2_Warped.nii.gz
	fslmaths xfm_dir/T1_brain_mask_to_FA_r_dilx2_Warped.nii.gz -bin $@ ;\

dti/dtifit/dti_FA_brain.nii.gz: dti/brainmask.nii.gz dti/dtifit/dti_FA.nii.gz 
	fslmaths dti/dtifit/dti_FA.nii.gz -mas $(word 1,$^) $@ ;\

#This is important for template creation!
xfm_dir/dti_FA_brain_to_MNI_r_Warped.nii.gz: dti/dtifit/dti_FA_brain.nii.gz
	antsRegistrationSyN.sh -d 3 -n 20 -t r -f /usr/share/fsl/data/standard/MNI152_T1_2mm_brain.nii.gz -m dti/dtifit/dti_FA_brain.nii.gz -o xfm_dir/dti_FA_brain_to_MNI_r_ ;\

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

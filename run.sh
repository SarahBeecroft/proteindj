#!/bin/bash -l
#SBATCH --job-name=proteindj
#SBATCH --time=3:00:00
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=20GB
#SBATCH --account=pawsey0012
#SBATCH --partition=work


# Load singularity module.
module load singularity/3.11.4-nompi
module load nextflow/25.04.6

export NXF_SINGULARITY_CACHEDIR=$MYSCRATCH/containers/
export SINGULARITY_CACHEDIR=$MYSCRATCH/containers/

nextflow run main.nf -c pawsey.config \
    --design_mode bindcraft_denovo --profile test,bindcraft_denovo,rfd_bindcraft_binder \
    -resume \
    --num_designs 1 --seqs_per_design 1 --design_length 5 \
    --input_pdb benchmarkdata/5o45_pd-l1.pdb \
    --rfd_partialdiff_timesteps 20

    # options: bindcraft_denovo, boltzgen_denovo, boltzgen_motifscaff, rfd_denovo, rfd_foldcond, rfd_motifscaff, rfd_partialdiff
    # Please provide input PDB file path required by bindcraft_denovo mode

    # Worked
    # rfd_denovo
    # rfd_foldcond
    # rfd_motifscaff
    # rfd_partialdiff 
# specific profile names are in the nextflow.config file, but the naming is a bit messy
# Still need to specify the design mode, which is one of the following: bindcraft_denovo, boltzgen_denovo, boltzgen_motifscaff, rfd_denovo, rfd_foldcond, rfd_motifscaff, rfd_partialdiff

## COMBOS TO TEST
# design_mode	profiles
#    --design_mode rfd_denovo --profile test,rfd_denovo_monomer,rfd_denovo_binder,af2_boltz_pred \ DONE
#
#    --design_mode rfd_foldcond --profile test,rfd_foldcond_monomer,rfd_foldcond_binder,af2_boltz_pred \ DONE
#
#    --design_mode rfd_motifscaff --profile test,rfd_motifscaff_monomer,rfd_motifscaff_binder,af2_boltz_pred \ DONE
#
#    --design_mode rfd_partialdiff --profile test,rfd_partialdiff_monomer,rfd_partialdiff_binder,af2_boltz_pred \ DONE
#
#    --design_mode bindcraft_denovo --profile test,bindcraft_denovo,rfd_bindcraft_binder \ FAILED bindcraft: Trajectory starting confidence low?? also seems like the failure status didn't kill the job, so it kept running and using up resources. Need to check the logs to see what happened. Maybe the bindcraft_denovo profile is not set up correctly?
#
#    --design_mode boltzgen_denovo --profile test,boltzgen_denovo_monomer,boltzgen_denovo_binder,af2_boltz_pred \ DONE (can't have     --motifscaff_inpaint_seq 'A17-19,A129-131'  in the command line for boltzgen_denovo, because it will throw an error. The motifscaff_inpaint_seq option is only for boltzgen_motifscaff mode but also doesn't error for other modes)  DONE was sneaky and added --use_kernels false to the bg module locally as a workaround
#
#    --design_mode boltzgen_motifscaff --profile test,boltzgen_motifscaff_monomer,boltzgen_motifscaff_binder,af2_boltz_pred \
#    --motifscaff_inpaint_seq 'A17-19,A129-131' \ DONE was sneaky and added --use_kernels false to the bg module locally as a workaround
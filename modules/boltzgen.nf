process PrepBG {
    label 'python_tools'

    input:
    val(batch_id)
    path(input_pdb)
    val(design_mode)

    output:
    tuple path("batch*.yaml"), val(batch_id), val(design_mode), path("*_boltzgen.pdb")

    script:
    """
    # Monomer boltzgen_denovo has no target - input_pdb is the NO_FILE placeholder in that case
    INPUT_PDB_ARG=""
    if [ "\$(basename ${input_pdb})" != "NO_FILE" ]; then
        INPUT_PDB_ARG="--input_pdb ${input_pdb}"
    fi

    python /scripts/generate_boltzgen_yaml.py \
        \$INPUT_PDB_ARG \
        --design_mode ${design_mode} \
        --design_length "${params.design_length}" \
        --hotspot_residues "${params.hotspot_residues ?: ''}" \
        --bg_not_binding_residues "${params.bg_not_binding_residues ?: ''}" \
        --motifscaff_spec "${params.motifscaff_spec ?: ''}" \
        --motifscaff_inpaint_seq "${params.motifscaff_inpaint_seq ?: ''}" \
        --flexible_residues "${params.flexible_residues ?: ''}" \
        --output batch${batch_id}.yaml
    """
}

process RunBG {
    label 'BG'
    label 'gpu'

    publishDir "${params.out_dir}/run/bg", mode: 'copy', pattern: "*.log"

    input:
    tuple path(spec_yaml), val(batch_id), val(design_mode), path(clean_pdb)
    val(batch_size)

    output:
    path "*.log"
    tuple path("bg_results/intermediate_designs/*.cif"), path("bg_results/intermediate_designs/*.npz"), emit: cifs_npzs, optional: true

    script:
    // Denovo diffuses a new binder from scratch; redesign rediffuses residues of an existing chain
    def protocol = design_mode == 'boltzgen_motifscaff' ? 'protein-redesign' : 'protein-anything'
    """
    # Ensure a failure in the piped boltzgen command below is not masked by tee's own exit code
    set -o pipefail

    # We specify a tmp/cache directory as some python packages try to write to the user home directory outside the container
    mkdir -p "\$PWD/tmp"
    export XDG_CACHE_HOME="\$PWD/tmp"
    export MPLCONFIGDIR="\$PWD/tmp"
    export NUMBA_CACHE_DIR="\$PWD/tmp"
    export TRITON_CACHE_DIR="\$PWD/tmp"

    boltzgen run ${spec_yaml} \
        --protocol ${protocol} \
        --steps design \
        --skip_inverse_folding \
        --design_checkpoints /cache/boltzgen1_diverse.ckpt /cache/boltzgen1_adherence.ckpt \
        --moldir /cache/mols.zip \
        --num_designs ${batch_size} \
        --devices 1 \
        --output bg_results \
        --cache /cache \
        --use_kernels false \
        2>&1 | tee boltzgen_${task.index}.log
    """
}

process AnalyseBG {
    label 'python_tools'
    publishDir "${params.out_dir}/run/bg", mode: 'copy', pattern: "boltzgen_analysis.log"

    input:
    path(cifs_npzs)
    val(design_mode)

    output:
    tuple path("processed/*.pdb"), path("processed/*.json"), emit: pdbs_jsons
    path "boltzgen_analysis.log"
    path("boltzgen_metadata.jsonl"), topic: metadata_ch_fold

    script:
    """
    # Ensure a failure in either piped command below is not masked by tee's own exit code
    set -o pipefail

    # Converts BoltzGen .cif+.npz outputs to fold_N.pdb/fold_N.json, relabels chains
    # A/B/... in file order, and inverts design_mask -> bg_inpaint_seq
    python /scripts/analyse_boltzgen.py \
        --input_dir ./ \
        --output_dir processed \
        --design_mode ${design_mode} \
        2>&1 | tee boltzgen_analysis.log

    python /scripts/metadata_converter.py \
        --converter bg \
        --input_dir processed \
        --input_ext .json \
        --output_file boltzgen_metadata.jsonl
    """
}

class BoltzGenEngine extends DesignEngine {

    BoltzGenEngine(Map params, boolean isBinderMode) {
        super(params, isBinderMode)
    }

    boolean requiresInputPdb() {
        return params.design_mode == 'boltzgen_motifscaff' || isBinderMode
    }

    void validateParams() {
        if (params.design_mode == 'boltzgen_denovo') {
            Utils.validateDesignLength(params.design_length)
        }

        if (params.hotspot_residues && !params.hotspot_residues.matches(Utils.RESIDUE_SPEC_REGEX)) {
            throw new IllegalArgumentException("hotspot_residues format invalid. Acceptable: 'A56,A115-120,B' (chain identifier is required).")
        }
        if (params.bg_not_binding_residues && !params.bg_not_binding_residues.matches(Utils.RESIDUE_SPEC_REGEX)) {
            throw new IllegalArgumentException("bg_not_binding_residues format invalid. Acceptable: 'A200,A210-215,B'.")
        }
        if (params.design_mode == 'boltzgen_denovo' && !params.input_pdb && (params.hotspot_residues || params.bg_not_binding_residues)) {
            throw new IllegalArgumentException("hotspot_residues/bg_not_binding_residues require a target - please provide input_pdb, or leave them null for monomer design.")
        }
        if (params.bg_use_kernels != null && !(params.bg_use_kernels.toString().toLowerCase() in ['auto', 'true', 'false'])) {
            throw new IllegalArgumentException("bg_use_kernels must be one of 'auto', 'true' or 'false'.")
        }
        if (params.flexible_residues && !params.flexible_residues.matches(Utils.RESIDUE_SPEC_REGEX)) {
            throw new IllegalArgumentException("flexible_residues format invalid. Acceptable: 'A10-13,A16,B'.")
        }
        if (params.motifscaff_spec) {
            if (params.design_mode == 'boltzgen_denovo') {
                throw new IllegalArgumentException("motifscaff_spec only applies to boltzgen_motifscaff mode.")
            }
            if (!params.motifscaff_spec.matches(Utils.MOTIFSCAFF_SPEC_REGEX)) {
                throw new IllegalArgumentException("motifscaff_spec format invalid. Must be an ordered list of chain-A keep tokens ('A<start>-<end>') and/or bare insert-count tokens ('<n>' or '<min>-<max>'), e.g. '7-10,A1-60,5,A70-100,10'.")
            }
        }
        if (params.motifscaff_inpaint_seq) {
            if (params.design_mode == 'boltzgen_denovo') {
                throw new IllegalArgumentException("motifscaff_inpaint_seq only applies to boltzgen_motifscaff mode.")
            }
            if (!params.motifscaff_inpaint_seq.matches(Utils.DESIGN_CHAIN_SPEC_REGEX)) {
                throw new IllegalArgumentException("motifscaff_inpaint_seq format invalid. Must reference chain A only, e.g. 'A10-50,A60'.")
            }
        }
        if (params.design_mode == 'boltzgen_motifscaff' && !params.motifscaff_spec && !params.motifscaff_inpaint_seq && !params.flexible_residues) {
            throw new IllegalArgumentException("boltzgen_motifscaff mode requires at least one of motifscaff_spec, motifscaff_inpaint_seq, or flexible_residues to be set - otherwise chain A would be left completely unchanged (wasted computation).")
        }
    }

    List<String> startupMessages() {
        def messages = []
        if (params.design_mode == 'boltzgen_denovo') {
            messages << (isBinderMode ? "Using BoltzGen to diffuse binders with the following design parameters:" : "Using BoltzGen to diffuse monomers with the following design parameters:")
            messages << "* Design length = ${params.design_length}"
        } else {
            messages << (isBinderMode ? "Using BoltzGen to motif-scaffold an existing binder with the following design parameters:" : "Using BoltzGen to motif-scaffold an existing monomer with the following design parameters:")
        }
        if (params.hotspot_residues) {
            messages << "* Target hotspots = ${params.hotspot_residues}"
        }
        if (params.bg_not_binding_residues) {
            messages << "* Target anti-hotspots = ${params.bg_not_binding_residues}"
        }
        if (params.design_mode == 'boltzgen_motifscaff' && params.motifscaff_spec) {
            messages << "* Motif scaffold spec = ${params.motifscaff_spec}"
        }
        if (params.design_mode == 'boltzgen_motifscaff' && params.motifscaff_inpaint_seq) {
            messages << "* Motif scaffold inpaint seq = ${params.motifscaff_inpaint_seq}"
        }
        if (params.flexible_residues) {
            messages << "* Flexible residues = ${params.flexible_residues}"
        }
        if (params.bg_use_kernels != null && params.bg_use_kernels.toString().toLowerCase() != 'auto') {
            messages << "* Use kernels = ${params.bg_use_kernels.toString().toLowerCase()}"
        }
        return messages
    }

    List<String> collectInputFiles() {
        return params.input_pdb ? [params.input_pdb] : []
    }
}

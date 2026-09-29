"""Tier A unit tests for metadata_converter.py."""
import json
import logging
import pickle

import numpy as np
import pandas as pd
import pytest

from metadata_converter import (
    MetadataConverter,
    AF2MetadataConverter,
    BCMetadataConverter,
    BGMetadataConverter,
    BoltzMetadataConverter,
    FAMPNNMetadataConverter,
    MPNNMetadataConverter,
    RFDMetadataConverter,
)


# ---------------------------------------------------------------------------
# MetadataConverter._is_fold_id_present
# ---------------------------------------------------------------------------

class TestIsFoldIdPresent:
    def test_present(self):
        conv = MetadataConverter()
        combined = {(0, 1): {}, (0, 2): {}, (1, None): {}}
        assert conv._is_fold_id_present(combined, 0) is True

    def test_absent(self):
        conv = MetadataConverter()
        combined = {(0, 1): {}}
        assert conv._is_fold_id_present(combined, 5) is False


# ---------------------------------------------------------------------------
# AF2MetadataConverter
# ---------------------------------------------------------------------------

def _write_score_sc(path, header_cols, rows):
    with open(path, 'w') as f:
        f.write("SCORE: " + " ".join(header_cols) + "\n")
        for row in rows:
            f.write("SCORE: " + " ".join(str(v) for v in row) + "\n")


class TestAF2MetadataConverter:
    def test_field_prefixing_and_rounding_precision(self, tmp_path):
        path = tmp_path / "score.sc"
        header = ['iptm', 'pae_interaction', 'plddt_overall', 'rmsd_overall', 'time', 'description']
        _write_score_sc(path, header, [
            [0.85123, 10.126, 90.004, 1.234, 45.6, 'fold_0_seq_1_af2pred'],
        ])
        conv = AF2MetadataConverter()
        records = list(conv._parse_metadata(path))
        assert len(records) == 1
        record = records[0]
        # iptm is a "precise" field: rounded to 3dp
        assert record['af2_iptm'] == 0.851
        # other float fields: rounded to 2dp
        assert record['af2_pae_interaction'] == 10.13
        assert record['af2_plddt_overall'] == 90.0
        assert record['af2_rmsd_overall'] == 1.23
        # time gets rounded to 2dp then re-rounded to whole seconds
        assert record['af2_time'] == 46
        assert isinstance(record['af2_time'], int)
        # description kept unprefixed
        assert record['description'] == 'fold_0_seq_1_af2pred'

    def test_extracts_fold_id_and_seq_id_from_description(self, tmp_path):
        path = tmp_path / "score.sc"
        header = ['iptm', 'time', 'description']
        _write_score_sc(path, header, [
            [0.5, 10.0, 'fold_3_seq_7_af2pred'],
        ])
        conv = AF2MetadataConverter()
        record = list(conv._parse_metadata(path))[0]
        assert record['fold_id'] == 3
        assert record['seq_id'] == 7

    def test_non_matching_description_sets_fold_and_seq_id_none(self, tmp_path):
        path = tmp_path / "score.sc"
        header = ['iptm', 'time', 'description']
        _write_score_sc(path, header, [
            [0.5, 10.0, 'unrelated_name'],
        ])
        conv = AF2MetadataConverter()
        record = list(conv._parse_metadata(path))[0]
        assert record['fold_id'] is None
        assert record['seq_id'] is None

    def test_non_float_field_kept_as_raw_string(self, tmp_path):
        path = tmp_path / "score.sc"
        header = ['some_flag', 'time', 'description']
        _write_score_sc(path, header, [
            ['yes', 10.0, 'fold_0_seq_0_af2pred'],
        ])
        conv = AF2MetadataConverter()
        record = list(conv._parse_metadata(path))[0]
        assert record['af2_some_flag'] == 'yes'

    def test_unparseable_float_value_becomes_none(self, tmp_path):
        path = tmp_path / "score.sc"
        header = ['iptm', 'time', 'description']
        _write_score_sc(path, header, [
            ['N/A', 10.0, 'fold_0_seq_0_af2pred'],
        ])
        conv = AF2MetadataConverter()
        record = list(conv._parse_metadata(path))[0]
        assert record['af2_iptm'] is None

    def test_row_with_wrong_column_count_is_skipped(self, tmp_path):
        path = tmp_path / "score.sc"
        with open(path, 'w') as f:
            f.write("SCORE: iptm time description\n")
            f.write("SCORE: 0.5 10.0\n")  # missing description column
        conv = AF2MetadataConverter()
        records = list(conv._parse_metadata(path))
        assert records == []

    def test_missing_time_column_raises_keyerror(self, tmp_path):
        # af2_time is unconditionally read after the loop; if 'time' isn't in the
        # header this raises a KeyError (documented current behavior, not fixed).
        path = tmp_path / "score.sc"
        header = ['iptm', 'description']
        _write_score_sc(path, header, [
            [0.5, 'fold_0_seq_0_af2pred'],
        ])
        conv = AF2MetadataConverter()
        with pytest.raises(KeyError):
            list(conv._parse_metadata(path))

    def test_no_header_raises_value_error(self, tmp_path):
        path = tmp_path / "score.sc"
        path.write_text("not a score file\n")
        conv = AF2MetadataConverter()
        with pytest.raises(ValueError):
            list(conv._parse_metadata(path))


# ---------------------------------------------------------------------------
# BCMetadataConverter / BGMetadataConverter / BoltzMetadataConverter
# (all three simply yield JSON file contents directly)
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("converter_cls", [BCMetadataConverter, BGMetadataConverter, BoltzMetadataConverter])
class TestPassthroughJsonConverters:
    def test_yields_json_contents_directly(self, tmp_path, converter_cls):
        path = tmp_path / "fold_0.json"
        path.write_text(json.dumps({'fold_id': 0, 'some_metric': 1.5}))
        conv = converter_cls()
        records = list(conv._parse_metadata(path))
        assert records == [{'fold_id': 0, 'some_metric': 1.5}]

    def test_invalid_json_yields_nothing(self, tmp_path, converter_cls):
        path = tmp_path / "fold_0.json"
        path.write_text("{not valid json")
        conv = converter_cls()
        records = list(conv._parse_metadata(path))
        assert records == []

    def test_missing_file_yields_nothing(self, tmp_path, converter_cls):
        path = tmp_path / "does_not_exist.json"
        conv = converter_cls()
        records = list(conv._parse_metadata(path))
        assert records == []


class TestBCMetadataConverterSaveJsonl:
    def test_save_jsonl_file_writes_all_records(self, tmp_path):
        f1 = tmp_path / "fold_0.json"
        f1.write_text(json.dumps({'fold_id': 0}))
        f2 = tmp_path / "fold_1.json"
        f2.write_text(json.dumps({'fold_id': 1}))
        out = tmp_path / "out.jsonl"

        conv = BCMetadataConverter()
        assert conv.save_jsonl_file([f1, f2], out) is True

        lines = out.read_text().splitlines()
        assert [json.loads(l)['fold_id'] for l in lines] == [0, 1]


# ---------------------------------------------------------------------------
# FAMPNNMetadataConverter / MPNNMetadataConverter
# ---------------------------------------------------------------------------

class TestFampnnMetadataConverter:
    def test_parses_expected_fields(self, tmp_path):
        path = tmp_path / "fold_0_seq_2.json"
        path.write_text(json.dumps({
            'design': 'fold_0_seq_2',
            'sequence': 'ACDEFG',
            'fampnn_avg_psce': '0.9876',
        }))
        conv = FAMPNNMetadataConverter()
        record = list(conv._parse_metadata(path))[0]
        assert record == {
            'description': 'fold_0_seq_2',
            'fold_id': 0,
            'seq_id': 2,
            'sequence': 'ACDEFG',
            'fampnn_avg_psce': 0.9876,
        }

    def test_non_matching_design_name_sets_ids_none(self, tmp_path):
        path = tmp_path / "x.json"
        path.write_text(json.dumps({
            'design': 'weird_name',
            'sequence': 'ACDEFG',
            'fampnn_avg_psce': '0.5',
        }))
        conv = FAMPNNMetadataConverter()
        record = list(conv._parse_metadata(path))[0]
        assert record['fold_id'] is None
        assert record['seq_id'] is None


class TestMpnnMetadataConverter:
    def test_parses_expected_fields_with_time(self, tmp_path):
        path = tmp_path / "fold_1_seq_3.json"
        path.write_text(json.dumps({
            'design': 'fold_1_seq_3',
            'sequence': 'ACDEFG',
            'score': '1.2345',
            'mpnn_time': '13',
        }))
        conv = MPNNMetadataConverter()
        record = list(conv._parse_metadata(path))[0]
        assert record == {
            'description': 'fold_1_seq_3',
            'fold_id': 1,
            'seq_id': 3,
            'sequence': 'ACDEFG',
            'mpnn_score': 1.2345,
            'mpnn_time': 13,
        }

    def test_missing_mpnn_time_is_none(self, tmp_path):
        path = tmp_path / "fold_1_seq_3.json"
        path.write_text(json.dumps({
            'design': 'fold_1_seq_3',
            'sequence': 'ACDEFG',
            'score': '1.0',
        }))
        conv = MPNNMetadataConverter()
        record = list(conv._parse_metadata(path))[0]
        assert record['mpnn_time'] is None


# ---------------------------------------------------------------------------
# RFDMetadataConverter
# ---------------------------------------------------------------------------

class _Unserializable:
    """Module-level class (required so it can be pickled) that json.dumps cannot serialize."""
    def __str__(self):
        return "custom-object"


class TestRfdMetadataConverter:
    def test_parses_trb_with_prefixed_keys(self, tmp_path):
        path = tmp_path / "fold_5.trb"
        trb_data = {
            'time': 12.7,
            'sampled_mask': np.array([True, False, True]),
            'note': 'some text',
        }
        with open(path, 'wb') as f:
            pickle.dump(trb_data, f)

        conv = RFDMetadataConverter()
        record = list(conv._parse_metadata(path))[0]
        assert record['fold_id'] == 5
        assert record['rfd_time'] == 13  # round(12.7) == 13
        assert record['rfd_sampled_mask'] == [True, False, True]
        assert record['rfd_note'] == 'some text'

    def test_non_serializable_value_converted_to_string(self, tmp_path):
        path = tmp_path / "fold_0.trb"
        trb_data = {'weird': _Unserializable()}
        with open(path, 'wb') as f:
            pickle.dump(trb_data, f)

        conv = RFDMetadataConverter()
        record = list(conv._parse_metadata(path))[0]
        assert record['rfd_weird'] == "custom-object"

    def test_no_fold_id_in_filename_is_none(self, tmp_path):
        path = tmp_path / "no_id_here.trb"
        with open(path, 'wb') as f:
            pickle.dump({'time': 1.0}, f)
        conv = RFDMetadataConverter()
        record = list(conv._parse_metadata(path))[0]
        assert record['fold_id'] is None


# ---------------------------------------------------------------------------
# merge_all()
# ---------------------------------------------------------------------------

def _write_jsonl(path, entries):
    with open(path, 'w') as f:
        for entry in entries:
            f.write(json.dumps(entry) + '\n')

class TestMergeAll:
    @pytest.mark.parametrize("entries", [
        [
            {'fold_id': 0, 'seq_id': 1, 'description': 'fold_0_seq_1', 'mpnn_score': 0.5},
            {'fold_id': 0, 'seq_id': 1, 'description': 'fold_0_seq_1_af2pred', 'af2_iptm': 0.8},
        ],
        [
            {'fold_id': 0, 'seq_id': 1, 'description': 'fold_0_seq_1_af2pred', 'af2_iptm': 0.8},
            {'fold_id': 0, 'seq_id': 1, 'description': 'fold_0_seq_1', 'mpnn_score': 0.5},
        ],
    ])
    def test_prediction_description_beats_sequence_description_in_any_order(self, tmp_path, entries):
        fold_file = tmp_path / "fold.jsonl"
        _write_jsonl(fold_file, [{'fold_id': 0, 'rfd_time': 100}])
        fold_seq_file = tmp_path / "fold_seq.jsonl"
        _write_jsonl(fold_seq_file, entries)
        out_file = tmp_path / "out.csv"

        conv = MetadataConverter()
        assert conv.merge_all(str(fold_file), str(fold_seq_file), str(out_file)) is True

        row = pd.read_csv(out_file).iloc[0]
        assert row['description'] == 'fold_0_seq_1_af2pred'

    @pytest.mark.parametrize("entries", [
        [
            {'fold_id': 2, 'seq_id': 3, 'description': 'fold_2_seq_3_af2pred', 'af2_iptm': 0.8},
            {'fold_id': 2, 'seq_id': 3, 'description': 'fold_2_seq_3_boltzpred', 'boltz_ptm': 0.9},
            {'fold_id': 2, 'seq_id': 3, 'description': 'fold_2_seq_3_boltzpred', 'pr_RoG': 12.0},
        ],
        [
            {'fold_id': 2, 'seq_id': 3, 'description': 'fold_2_seq_3_boltzpred', 'pr_RoG': 12.0},
            {'fold_id': 2, 'seq_id': 3, 'description': 'fold_2_seq_3_boltzpred', 'boltz_ptm': 0.9},
            {'fold_id': 2, 'seq_id': 3, 'description': 'fold_2_seq_3_af2pred', 'af2_iptm': 0.8},
        ],
    ])
    def test_analysis_description_is_authoritative_in_any_order(self, tmp_path, entries):
        fold_file = tmp_path / "fold.jsonl"
        _write_jsonl(fold_file, [{'fold_id': 2, 'description': 'fold_2'}])
        fold_seq_file = tmp_path / "fold_seq.jsonl"
        _write_jsonl(fold_seq_file, entries)
        out_file = tmp_path / "out.csv"

        conv = MetadataConverter()
        assert conv.merge_all(str(fold_file), str(fold_seq_file), str(out_file)) is True

        row = pd.read_csv(out_file).iloc[0]
        assert row['description'] == 'fold_2_seq_3_boltzpred'

    def test_description_with_mismatched_ids_is_ignored(self, tmp_path, caplog):
        fold_file = tmp_path / "fold.jsonl"
        _write_jsonl(fold_file, [{'fold_id': 0}])
        fold_seq_file = tmp_path / "fold_seq.jsonl"
        _write_jsonl(fold_seq_file, [
            {'fold_id': 0, 'seq_id': 1, 'description': 'fold_0_seq_1', 'mpnn_score': 0.5},
            {'fold_id': 0, 'seq_id': 1, 'description': 'fold_9_seq_9_af2pred', 'af2_iptm': 0.8},
        ])
        out_file = tmp_path / "out.csv"

        conv = MetadataConverter()
        with caplog.at_level(logging.WARNING):
            assert conv.merge_all(str(fold_file), str(fold_seq_file), str(out_file)) is True

        row = pd.read_csv(out_file).iloc[0]
        assert row['description'] == 'fold_0_seq_1'
        assert "do not match metadata key" in caplog.text

    def test_merges_fold_only_metadata_into_fold_seq_entries(self, tmp_path):
        fold_file = tmp_path / "fold.jsonl"
        _write_jsonl(fold_file, [{'fold_id': 0, 'rfd_time': 100}])
        fold_seq_file = tmp_path / "fold_seq.jsonl"
        _write_jsonl(fold_seq_file, [
            {'fold_id': 0, 'seq_id': 1, 'description': 'fold_0_seq_1', 'mpnn_score': 0.5},
        ])
        out_file = tmp_path / "out.csv"

        conv = MetadataConverter()
        assert conv.merge_all(str(fold_file), str(fold_seq_file), str(out_file)) is True

        df = pd.read_csv(out_file)
        assert len(df) == 1
        row = df.iloc[0]
        assert row['fold_id'] == 0
        assert row['seq_id'] == 1
        assert row['rfd_time'] == 100
        assert row['mpnn_score'] == 0.5

    def test_fold_only_entry_without_seq_entry_is_included(self, tmp_path):
        fold_file = tmp_path / "fold.jsonl"
        _write_jsonl(fold_file, [
            {'fold_id': 0, 'rfd_time': 100},
            {'fold_id': 1, 'rfd_time': 200},
        ])
        fold_seq_file = tmp_path / "fold_seq.jsonl"
        _write_jsonl(fold_seq_file, [
            {'fold_id': 0, 'seq_id': 1, 'description': 'fold_0_seq_1', 'mpnn_score': 0.5},
        ])
        out_file = tmp_path / "out.csv"

        conv = MetadataConverter()
        assert conv.merge_all(str(fold_file), str(fold_seq_file), str(out_file)) is True

        df = pd.read_csv(out_file)
        assert len(df) == 2
        fold_only_row = df[df['fold_id'] == 1].iloc[0]
        assert fold_only_row['description'] == 'fold_1'
        assert fold_only_row['rfd_time'] == 200
        # seq_id should be blank (NaN) for fold-only rows, not 0.0
        assert pd.isna(fold_only_row['seq_id'])

    def test_empty_fold_seq_file_is_handled(self, tmp_path):
        fold_file = tmp_path / "fold.jsonl"
        _write_jsonl(fold_file, [{'fold_id': 0, 'rfd_time': 100}])
        fold_seq_file = tmp_path / "fold_seq.jsonl"
        fold_seq_file.write_text("")  # empty file
        out_file = tmp_path / "out.csv"

        conv = MetadataConverter()
        assert conv.merge_all(str(fold_file), str(fold_seq_file), str(out_file)) is True

        df = pd.read_csv(out_file)
        assert len(df) == 1
        assert df.iloc[0]['fold_id'] == 0

    def test_empty_columns_are_dropped(self, tmp_path):
        fold_file = tmp_path / "fold.jsonl"
        _write_jsonl(fold_file, [{'fold_id': 0}])  # no rfd_time at all
        fold_seq_file = tmp_path / "fold_seq.jsonl"
        _write_jsonl(fold_seq_file, [
            {'fold_id': 0, 'seq_id': 1, 'description': 'fold_0_seq_1', 'mpnn_score': 0.5},
        ])
        out_file = tmp_path / "out.csv"

        conv = MetadataConverter()
        conv.merge_all(str(fold_file), str(fold_seq_file), str(out_file))

        df = pd.read_csv(out_file)
        assert 'rfd_time' not in df.columns

    def test_seq_id_written_as_integer_not_float(self, tmp_path):
        fold_file = tmp_path / "fold.jsonl"
        _write_jsonl(fold_file, [{'fold_id': 0, 'rfd_time': 100}])
        fold_seq_file = tmp_path / "fold_seq.jsonl"
        _write_jsonl(fold_seq_file, [
            {'fold_id': 0, 'seq_id': 1, 'description': 'fold_0_seq_1', 'mpnn_score': 0.5},
        ])
        out_file = tmp_path / "out.csv"

        conv = MetadataConverter()
        conv.merge_all(str(fold_file), str(fold_seq_file), str(out_file))

        # Read as raw text to confirm seq_id column is "1" not "1.0"
        content = out_file.read_text()
        header = content.splitlines()[0].split(',')
        seq_id_idx = header.index('seq_id')
        data_row = content.splitlines()[1].split(',')
        assert data_row[seq_id_idx] == '1'

    def test_unrecognized_fields_dropped_from_output(self, tmp_path):
        # Only fields present in metadata_field_names are kept - any other
        # key in the input JSONL is silently dropped from the output CSV.
        fold_file = tmp_path / "fold.jsonl"
        _write_jsonl(fold_file, [{'fold_id': 0, 'rfd_time': 100, 'totally_unknown_field': 'x'}])
        fold_seq_file = tmp_path / "fold_seq.jsonl"
        fold_seq_file.write_text("")
        out_file = tmp_path / "out.csv"

        conv = MetadataConverter()
        conv.merge_all(str(fold_file), str(fold_seq_file), str(out_file))

        df = pd.read_csv(out_file)
        assert 'totally_unknown_field' not in df.columns

    def test_fold_only_count_log_message_reports_correct_count(self, tmp_path, caplog):
        # `fold_only_count` is incremented per fold-only entry added, so the log
        # message must report the actual count, not 0.
        import logging
        fold_file = tmp_path / "fold.jsonl"
        _write_jsonl(fold_file, [{'fold_id': 7, 'rfd_time': 100}])
        fold_seq_file = tmp_path / "fold_seq.jsonl"
        fold_seq_file.write_text("")
        out_file = tmp_path / "out.csv"

        conv = MetadataConverter()
        with caplog.at_level(logging.INFO):
            conv.merge_all(str(fold_file), str(fold_seq_file), str(out_file))

        # A fold-only entry (fold_id=7) was in fact added...
        df = pd.read_csv(out_file)
        assert len(df) == 1
        # ...and the log reports the actual count.
        assert "Added 1 fold-only entries" in caplog.text

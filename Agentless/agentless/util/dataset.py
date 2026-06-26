import json
import os

from datasets import Dataset, DatasetDict, load_dataset


def load_swebench_dataset(dataset: str, split: str | None = "test"):
    """Load an official SWE-bench dataset name or a local JSON snapshot."""
    if os.path.isfile(dataset):
        with open(dataset, "r") as f:
            rows = json.load(f)
        if not isinstance(rows, list):
            raise ValueError(f"Expected a JSON list in local dataset file: {dataset}")
        ds = Dataset.from_list(rows)
        if split is None:
            return DatasetDict({"test": ds})
        return ds

    if split is None:
        return load_dataset(dataset)
    return load_dataset(dataset, split=split)

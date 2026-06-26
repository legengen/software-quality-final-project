#!/usr/bin/env python3
"""Evaluate model patches for the custom concurrency benchmark."""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import tempfile
from pathlib import Path


def load_json_rows(path: Path) -> list[dict]:
    if path.suffix == ".jsonl":
        return [
            json.loads(line)
            for line in path.read_text(encoding="utf-8").splitlines()
            if line.strip()
        ]
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, list):
        raise ValueError(f"Expected a JSON list: {path}")
    return data


def run(cmd: list[str], cwd: Path, input_text: str | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(
        cmd,
        cwd=cwd,
        input=input_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )


def apply_patch(repo_dir: Path, patch_text: str) -> tuple[bool, str]:
    if not patch_text.strip():
        return True, "empty patch treated as no-op"
    outputs = []
    for strip_count in ("1", "2"):
        result = run(
            ["git", "apply", "--whitespace=nowarn", f"-p{strip_count}", "-"],
            repo_dir,
            patch_text,
        )
        outputs.append(f"git apply -p{strip_count}:\n{result.stdout}")
        if result.returncode == 0:
            return True, "\n".join(outputs)
    return False, "\n".join(outputs)


def pytest_selectors(raw: str) -> list[str]:
    parsed = json.loads(raw)
    if not isinstance(parsed, list):
        raise ValueError(f"Expected test selector list, got: {raw}")
    return parsed


def evaluate_one(
    case: dict,
    prediction: dict,
    benchmark_root: Path,
    keep_tmp: bool,
    python_executable: str,
) -> dict:
    patch = prediction.get("model_patch") or prediction.get("patch") or ""
    tmp_ctx = None
    if keep_tmp:
        tmp_path = Path(tempfile.mkdtemp(prefix=f"{case['instance_id']}__"))
    else:
        tmp_ctx = tempfile.TemporaryDirectory(prefix=f"{case['instance_id']}__")
        tmp_path = Path(tmp_ctx.name)
    repo_dir = tmp_path / "repo"
    shutil.copytree(benchmark_root, repo_dir)

    git_init = run(["git", "init"], repo_dir)
    if git_init.returncode != 0:
        raise RuntimeError(git_init.stdout)
    run(["git", "config", "user.name", "custom-concurrency-eval"], repo_dir)
    run(["git", "config", "user.email", "custom-concurrency-eval@example.local"], repo_dir)
    git_add = run(["git", "add", "."], repo_dir)
    if git_add.returncode != 0:
        raise RuntimeError(git_add.stdout)
    git_commit = run(["git", "commit", "-m", "base"], repo_dir)
    if git_commit.returncode != 0:
        raise RuntimeError(git_commit.stdout)

    test_patch_ok, test_patch_output = apply_patch(repo_dir, case["test_patch"])
    model_patch_ok = False
    model_patch_output = ""
    if test_patch_ok:
        model_patch_ok, model_patch_output = apply_patch(repo_dir, patch)

    selectors = pytest_selectors(case["FAIL_TO_PASS"]) + pytest_selectors(case["PASS_TO_PASS"])
    if test_patch_ok and model_patch_ok:
        test_result = run([python_executable, "-m", "pytest", "-q", *selectors], repo_dir)
    else:
        test_result = subprocess.CompletedProcess([], 1, stdout="patch application failed")

    resolved = test_patch_ok and model_patch_ok and test_result.returncode == 0
    result = {
        "instance_id": case["instance_id"],
        "resolved": resolved,
        "test_patch_applied": test_patch_ok,
        "model_patch_applied": model_patch_ok,
        "pytest_exit_code": test_result.returncode,
        "FAIL_TO_PASS": pytest_selectors(case["FAIL_TO_PASS"]),
        "PASS_TO_PASS": pytest_selectors(case["PASS_TO_PASS"]),
        "test_patch_output": test_patch_output,
        "model_patch_output": model_patch_output,
        "test_output": test_result.stdout,
    }

    if keep_tmp:
        result["workdir"] = str(repo_dir)
    elif tmp_ctx is not None:
        tmp_ctx.cleanup()

    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset", required=True, type=Path)
    parser.add_argument("--predictions", required=True, type=Path)
    parser.add_argument("--benchmark-root", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--python", default="python3")
    parser.add_argument("--keep-tmp", action="store_true")
    args = parser.parse_args()

    cases = {row["instance_id"]: row for row in load_json_rows(args.dataset)}
    predictions = load_json_rows(args.predictions)
    results = []
    for prediction in predictions:
        instance_id = prediction["instance_id"]
        if instance_id not in cases:
            raise KeyError(f"Prediction has unknown instance_id: {instance_id}")
        results.append(
            evaluate_one(
                cases[instance_id],
                prediction,
                args.benchmark_root,
                args.keep_tmp,
                args.python,
            )
        )

    summary = {
        "total": len(results),
        "resolved": sum(1 for result in results if result["resolved"]),
        "unresolved": sum(1 for result in results if not result["resolved"]),
    }
    payload = {"summary": summary, "results": results}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False))
    return 0 if summary["unresolved"] == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())

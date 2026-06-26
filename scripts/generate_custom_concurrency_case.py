#!/usr/bin/env python3
"""Generate the custom AGENTLESS-style concurrency case resources."""

from __future__ import annotations

import ast
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BENCHMARK_ROOT = ROOT / "benchmarks" / "concurrent_counter"
AGENTLESS_ROOT = ROOT / "Agentless"
RESOURCE_ROOT = AGENTLESS_ROOT / "resources" / "custom_concurrency"
INSTANCE_ID = "local_concurrency__counter-0001"
REPO = "local/concurrent_counter"
BASE_COMMIT = "local-concurrency-base"


TEST_PATCH = """diff --git a/tests/test_counter_thread_safety.py b/tests/test_counter_thread_safety.py
new file mode 100644
--- /dev/null
+++ b/tests/test_counter_thread_safety.py
@@ -0,0 +1,24 @@
+from concurrent.futures import ThreadPoolExecutor
+
+from concurrent_counter import ConcurrentCounter
+
+
+def _increment_many(counter, count):
+    for _ in range(count):
+        counter.increment()
+
+
+def test_parallel_increment_is_thread_safe():
+    counter = ConcurrentCounter()
+    workers = 8
+    increments_per_worker = 250
+
+    with ThreadPoolExecutor(max_workers=workers) as executor:
+        futures = [
+            executor.submit(_increment_many, counter, increments_per_worker)
+            for _ in range(workers)
+        ]
+        for future in futures:
+            future.result()
+
+    assert counter.value == workers * increments_per_worker
"""


GOLD_PATCH = '''diff --git a/concurrent_counter/counter.py b/concurrent_counter/counter.py
index 3f72ed1..533ce77 100644
--- a/concurrent_counter/counter.py
+++ b/concurrent_counter/counter.py
@@ -1,3 +1,4 @@
+import threading
 import time
 
 
@@ -6,6 +7,7 @@ class ConcurrentCounter:
 
     def __init__(self, initial=0):
         self._value = initial
+        self._lock = threading.Lock()
 
     @property
     def value(self):
@@ -17,10 +19,12 @@ class ConcurrentCounter:
         This implementation is intentionally not thread-safe: two threads can
         read the same old value and then overwrite each other's update.
         """
-        old_value = self._value
-        time.sleep(0.00001)
-        self._value = old_value + amount
-        return self._value
+        with self._lock:
+            old_value = self._value
+            time.sleep(0.00001)
+            self._value = old_value + amount
+            return self._value
 
     def reset(self):
-        self._value = 0
+        with self._lock:
+            self._value = 0
'''


PROBLEM_STATEMENT = """ConcurrentCounter loses updates when incremented from multiple threads

The small `concurrent_counter` package exposes `ConcurrentCounter.increment()` for callers that
share a counter across worker threads. Sequential increments work correctly, but concurrent calls
can lose updates.

Reproduction:

```python
from concurrent.futures import ThreadPoolExecutor
from concurrent_counter import ConcurrentCounter

counter = ConcurrentCounter()
workers = 8
increments_per_worker = 250

with ThreadPoolExecutor(max_workers=workers) as executor:
    futures = [
        executor.submit(lambda: [counter.increment() for _ in range(increments_per_worker)])
        for _ in range(workers)
    ]
    for future in futures:
        future.result()

assert counter.value == workers * increments_per_worker
```

The assertion should always pass. In the current implementation it can fail because multiple
threads observe the same old counter value and overwrite each other's updates. Fix the counter so
that concurrent increments are safe while keeping the existing sequential behavior and reset API.
"""


def parse_python_file(path: Path) -> dict:
    source = path.read_text(encoding="utf-8")
    tree = ast.parse(source)
    classes = []
    functions = []
    class_methods = set()

    for node in ast.walk(tree):
        if isinstance(node, ast.ClassDef):
            methods = []
            for item in node.body:
                if isinstance(item, ast.FunctionDef):
                    methods.append(
                        {
                            "name": item.name,
                            "start_line": item.lineno,
                            "end_line": item.end_lineno,
                            "text": source.splitlines()[
                                item.lineno - 1 : item.end_lineno
                            ],
                        }
                    )
                    class_methods.add(item.name)
            classes.append(
                {
                    "name": node.name,
                    "start_line": node.lineno,
                    "end_line": node.end_lineno,
                    "text": source.splitlines()[node.lineno - 1 : node.end_lineno],
                    "methods": methods,
                }
            )
        elif isinstance(node, ast.FunctionDef) and node.name not in class_methods:
            functions.append(
                {
                    "name": node.name,
                    "start_line": node.lineno,
                    "end_line": node.end_lineno,
                    "text": source.splitlines()[node.lineno - 1 : node.end_lineno],
                }
            )

    return {
        "classes": classes,
        "functions": functions,
        "text": source.splitlines(),
    }


def create_structure(directory: Path) -> dict:
    structure: dict = {}
    repo_name = directory.name

    for path in sorted(directory.rglob("*")):
        if "__pycache__" in path.parts or path.is_dir():
            continue
        relative_parent = path.parent.relative_to(directory)
        parts = [repo_name]
        if str(relative_parent) != ".":
            parts.extend(relative_parent.parts)
        current = structure
        for part in parts:
            current = current.setdefault(part, {})
        if path.suffix == ".py":
            current[path.name] = parse_python_file(path)
        else:
            current[path.name] = {}

    return structure


def main() -> None:
    RESOURCE_ROOT.mkdir(parents=True, exist_ok=True)
    (RESOURCE_ROOT / "project_structures").mkdir(parents=True, exist_ok=True)

    case = {
        "repo": REPO,
        "instance_id": INSTANCE_ID,
        "base_commit": BASE_COMMIT,
        "patch": GOLD_PATCH,
        "test_patch": TEST_PATCH,
        "problem_statement": PROBLEM_STATEMENT,
        "hints_text": "",
        "created_at": "2026-06-26T00:00:00Z",
        "version": "custom-concurrency-1",
        "FAIL_TO_PASS": json.dumps(
            ["tests/test_counter_thread_safety.py::test_parallel_increment_is_thread_safe"]
        ),
        "PASS_TO_PASS": json.dumps(
            [
                "tests/test_counter.py::test_initial_value_defaults_to_zero",
                "tests/test_counter.py::test_sequential_increment_and_reset",
            ]
        ),
        "environment_setup_commit": BASE_COMMIT,
    }

    dataset_path = RESOURCE_ROOT / "concurrency_cases.json"
    dataset_path.write_text(
        json.dumps([case], ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    structure_payload = {
        "repo": REPO,
        "base_commit": BASE_COMMIT,
        "structure": create_structure(BENCHMARK_ROOT),
        "instance_id": INSTANCE_ID,
    }
    structure_path = RESOURCE_ROOT / "project_structures" / f"{INSTANCE_ID}.json"
    structure_path.write_text(
        json.dumps(structure_payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    gold_path = RESOURCE_ROOT / "gold_patch.jsonl"
    gold_path.write_text(
        json.dumps(
            {
                "model_name_or_path": "gold",
                "instance_id": INSTANCE_ID,
                "model_patch": GOLD_PATCH,
            },
            ensure_ascii=False,
        )
        + "\n",
        encoding="utf-8",
    )

    print(dataset_path)
    print(structure_path)
    print(gold_path)


if __name__ == "__main__":
    main()

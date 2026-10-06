# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

from __future__ import annotations

import base64
import hashlib
import json
import os
import time

import pytest

from musegadget import executor
from musegadget.executor import Account, Executor


@pytest.fixture
def ex(monkeypatch, tmp_path):
    src = os.path.join(os.path.dirname(__file__), "..", "src")
    monkeypatch.setenv("PYTHONPATH", os.path.abspath(src))
    account = Account.current()
    return Executor(Account(account.name, account.uid, account.gid, str(tmp_path)))


def _child_env_passes_pythonpath(monkeypatch, box=None):
    original = Executor._child_options

    def options(self):
        opts = original(self)
        opts["env"]["PYTHONPATH"] = os.environ["PYTHONPATH"]
        if box is not None:
            opts["env"]["MUSEBOX_ROOT"] = str(box)
        return opts

    monkeypatch.setattr(Executor, "_child_options", options)


@pytest.fixture
def box(tmp_path, monkeypatch):
    _child_env_passes_pythonpath(monkeypatch, tmp_path)
    (tmp_path / "tasks" / "t1" / "out").mkdir(parents=True)
    return tmp_path


def test_system_run_is_not_offered(ex):
    assert "system.run" not in executor.COMMAND_SPECS
    assert ex.run("system.run", {"command": "id"}) == {"ok": False, "error": "unsupported command: system.run"}


def test_clip_bounds_the_json_encoded_size():
    text, cut = executor._clip(b"x" * executor.MAX_OUTPUT_BYTES)
    assert (len(text), cut) == (executor.MAX_OUTPUT_BYTES, False)
    # Undecodable bytes become U+FFFD, which json.dumps writes as a 6-byte escape.
    text, cut = executor._clip(b"\xff" * executor.MAX_OUTPUT_BYTES)
    assert cut
    assert executor.MAX_OUTPUT_BYTES // 2 < len(json.dumps(text)) - 2 <= executor.MAX_OUTPUT_BYTES


def test_unknown_command(ex):
    assert ex.run("nope", {}) == {"ok": False, "error": "unsupported command: nope"}


def test_file_write_then_read_round_trip(ex, box):
    target = str(box / "tasks" / "t1" / "out" / "sub" / "blob.bin")
    data = os.urandom(150_000)
    chunks = [data[i:i + 65536] for i in range(0, len(data), 65536)]
    for i, chunk in enumerate(chunks):
        last = i == len(chunks) - 1
        result = ex.run("file.write", {
            "path": target, "offset": i * 65536, "data_b64": base64.b64encode(chunk).decode(),
            "final": last, "create_parents": True,
            "sha256": hashlib.sha256(data).hexdigest() if last else None,
        })
        assert result["ok"], result
    assert result["payload"]["complete"] and open(target, "rb").read() == data

    received, offset = b"", 0
    while True:
        result = ex.run("file.read", {"path": target, "offset": offset})
        assert result["ok"], result
        received += base64.b64decode(result["payload"]["data_b64"])
        offset = result["payload"]["next_offset"]
        if result["payload"]["eof"]:
            break
    assert received == data


def test_file_write_rejects_a_bad_checksum(ex, box):
    target = str(box / "tasks" / "t1" / "out" / "f")
    result = ex.run("file.write", {"path": target, "data_b64": "aGk=", "final": True, "sha256": "00"})
    assert not result["ok"] and "sha256" in result["error"]
    assert not os.path.exists(target)


def test_file_write_rejects_out_of_order_chunks(ex, box):
    target = str(box / "tasks" / "t1" / "out" / "f")
    assert ex.run("file.write", {"path": target, "data_b64": "aGk="})["ok"]
    result = ex.run("file.write", {"path": target, "data_b64": "aGk=", "offset": 5})
    assert not result["ok"] and "expected offset 2" in result["error"]


def test_file_paths_must_be_absolute(ex, box):
    result = ex.run("file.read", {"path": "relative.txt"})
    assert result == {"ok": False, "error": "path must be an absolute path"}


def test_file_read_stays_inside_the_box(ex, box, tmp_path_factory):
    (box / "README.md").write_text("hi")
    assert ex.run("file.read", {"path": str(box / "README.md")})["ok"]
    outside = tmp_path_factory.mktemp("outside") / "secret"
    outside.write_text("no")
    (box / "link").symlink_to(outside)
    for path in ("/etc/passwd", str(outside), str(box / "link"), str(box / ".." / "x")):
        result = ex.run("file.read", {"path": path})
        assert not result["ok"] and "only paths under" in result["error"], path


@pytest.mark.parametrize("rel", [
    "README.md", "tasks/t1/TASK.md", "tasks/t1/in/data.csv", "tasks/t1/out",
    "tasks/out/x", "tasks/t1/out/../TASK.md", "tasks/t1/outx/f",
])
def test_file_write_only_inside_a_task_out_dir(ex, box, rel):
    result = ex.run("file.write", {"path": str(box / rel), "data_b64": "aGk=", "final": True})
    assert not result["ok"] and "writes are allowed only under" in result["error"], rel


def test_file_write_refuses_a_symlinked_out_dir(ex, box):
    (box / "tasks" / "t2").mkdir()
    (box / "tasks" / "t2" / "out").symlink_to(box / "tasks" / "t1")
    result = ex.run("file.write", {"path": str(box / "tasks/t2/out/TASK.md"), "data_b64": "aGk=", "final": True})
    assert not result["ok"] and "writes are allowed only under" in result["error"]

def test_device_health_reports_basics(ex):
    payload = ex.run("device.health", {})["payload"]
    assert payload["version"] and payload["hostname"] and "disk_gb" in payload


def test_child_gets_the_service_box():
    assert ex_box_env() == executor.BOX


def ex_box_env():
    account = Account.current()
    return Executor(account)._child_options()["env"]["MUSEBOX_ROOT"]

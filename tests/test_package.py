"""Smoke test: the package imports and its version matches pyproject.toml."""

import tomllib
from pathlib import Path

import recon


def test_version_matches_pyproject() -> None:
    pyproject = Path(__file__).resolve().parents[1] / "pyproject.toml"
    with pyproject.open("rb") as fh:
        declared = tomllib.load(fh)["project"]["version"]
    assert recon.__version__ == declared

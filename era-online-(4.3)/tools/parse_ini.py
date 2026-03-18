"""
parse_ini.py - Shared INI file parser for Era Online VB6 data files.

The VB6 data files use Windows INI format (GetPrivateProfileString).
- [SECTION] headers
- Key=Value pairs
- ' lines are VB6 comments (ignored)
- ; lines are standard INI comments (ignored)
- CRLF or LF line endings
"""


class INIParser:
    def __init__(self, filepath: str):
        self._data: dict[str, dict[str, str]] = {}
        self._load(filepath)

    def _load(self, filepath: str) -> None:
        try:
            with open(filepath, "r", encoding="latin-1") as f:
                content = f.read()
        except FileNotFoundError:
            raise FileNotFoundError(f"INI file not found: {filepath}")

        current_section = ""
        for line in content.splitlines():
            line = line.strip()
            if not line or line.startswith(";") or line.startswith("'"):
                continue
            if line.startswith("[") and line.endswith("]"):
                current_section = line[1:-1].strip()
                if current_section not in self._data:
                    self._data[current_section] = {}
            elif "=" in line and current_section:
                key, _, value = line.partition("=")
                key = key.strip()
                value = value.strip()
                # Don't overwrite - first occurrence wins (matches GetPrivateProfileString)
                if key not in self._data[current_section]:
                    self._data[current_section][key] = value

    def get(self, section: str, key: str, default: str = "") -> str:
        sec = self._data.get(section, {})
        # Case-insensitive key lookup (VB6 INI is case-insensitive)
        for k, v in sec.items():
            if k.lower() == key.lower():
                return v
        return default

    def get_int(self, section: str, key: str, default: int = 0) -> int:
        val = self.get(section, key, "")
        try:
            return int(val) if val else default
        except (ValueError, TypeError):
            return default

    def get_float(self, section: str, key: str, default: float = 0.0) -> float:
        val = self.get(section, key, "")
        try:
            return float(val) if val else default
        except (ValueError, TypeError):
            return default

    def sections(self) -> list[str]:
        return list(self._data.keys())

    def has_section(self, section: str) -> bool:
        return section in self._data

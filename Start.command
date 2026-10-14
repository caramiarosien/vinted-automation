#!/bin/zsh
setopt NO_BGNICE
cd "$(dirname "$0")" || exit 1
PYTHON_BIN="$(command -v python3)"
if [ -x .venv/bin/python ]; then PYTHON_BIN="$PWD/.venv/bin/python"; fi
if ! "$PYTHON_BIN" -c 'from PIL import Image' 2>/dev/null; then
  echo 'Bitte zuerst installieren: python3 -m venv .venv && .venv/bin/pip install -r requirements.txt'
  read -r 'reply?Enter zum Schließen'
  exit 1
fi
if "$PYTHON_BIN" - <<'PY' 2>/dev/null
from urllib.request import urlopen
with urlopen('http://127.0.0.1:8765/', timeout=1) as response:
    assert b'<title>Vinted Werkstatt</title>' in response.read()
PY
then
  open 'http://127.0.0.1:8765'
  exit 0
fi
"$PYTHON_BIN" pipeline.py serve &
WORKSHOP_PID=$!
trap 'kill "$WORKSHOP_PID" 2>/dev/null' EXIT INT TERM
if "$PYTHON_BIN" - <<'PY'
from urllib.request import urlopen
import time
for attempt in range(25):
    try:
        with urlopen('http://127.0.0.1:8765/', timeout=1) as response:
            if b'<title>Vinted Werkstatt</title>' in response.read():
                raise SystemExit(0)
    except OSError:
        pass
    time.sleep(.2)
raise SystemExit(1)
PY
then
  open 'http://127.0.0.1:8765'
  wait "$WORKSHOP_PID"
else
  echo 'Die Werkstatt konnte nicht gestartet werden. Ist Port 8765 bereits belegt?'
  read -r 'reply?Enter zum Schließen'
fi

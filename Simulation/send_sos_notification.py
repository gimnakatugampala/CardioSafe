#!/usr/bin/env python3
"""Inject an FCM-shaped SOS message into an iOS simulator without APNs credentials."""
import argparse
import json
import subprocess
import tempfile
from pathlib import Path


def simulator_payload(staff_id, hospital_id):
    for value in (staff_id, hospital_id):
        if not value or len(value) > 128 or "/" in value:
            raise ValueError("Use valid staff and hospital identifiers.")
    message = {
        "notification": {
            "title": "CardioSafe · SOS notification test",
            "body": "Simulation alert. Tap to open your hospital’s live Firebase SOS inbox.",
        },
        "data": {
            "type": "hospital_sos", "simulation": "true",
            "hospitalID": hospital_id, "staffID": staff_id,
        },
    }
    # FCM forwards these notification/data fields through APNs on a configured app.
    return {"aps": {"alert": message["notification"], "sound": "default"}, **message["data"]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulator", required=True, help="Booted simulator UUID")
    parser.add_argument("--staff-id", required=True, help="Signed-in staff Firebase UID")
    parser.add_argument("--hospital-id", default="demo-asiri-central")
    args = parser.parse_args()
    payload = simulator_payload(args.staff_id, args.hospital_id)
    with tempfile.TemporaryDirectory(prefix="cardiosafe-sos-") as folder:
        path = Path(folder) / "sos.apns"
        path.write_text(json.dumps(payload), encoding="utf-8")
        subprocess.run(["xcrun", "simctl", "push", args.simulator, "gimnak.CardioSafe", str(path)], check=True)
    print("Injected simulation notification. No message was sent through FCM or APNs servers.")


if __name__ == "__main__":
    main()

import argparse
import json
import sys

PROJECT_ID = "cardio-safe"
DEMO_HOSPITAL_ID = "demo-asiri-central"


def planned_claims(user, expected_uid):
    if user.uid != expected_uid:
        raise ValueError("Account UID does not match the reviewed account. No access changed.")
    if user.disabled:
        raise ValueError("This account is disabled. No access changed.")
    if not user.email_verified:
        raise ValueError("Verify the email through its inbox before assigning staff access. No access changed.")
    claims = dict(user.custom_claims or {})
    if claims.get("role") not in (None, "patient", "staff"):
        raise ValueError("Review this account's existing role before changing it.")
    hospitals = claims.get("hospitalIDs", [])
    if not isinstance(hospitals, list) or any(not isinstance(item, str) for item in hospitals):
        raise ValueError("Existing hospital assignments need review. No access changed.")
    if any(item != DEMO_HOSPITAL_ID for item in hospitals):
        raise ValueError("This account has other hospital assignments. Review them separately.")
    claims.update(role="staff", hospitalIDs=[DEMO_HOSPITAL_ID])
    return claims


def main():
    parser = argparse.ArgumentParser(description="Inspect or assign staff access to CardioSafe's demo hospital using trusted admin credentials.")
    parser.add_argument("action", choices=["inspect", "grant"])
    parser.add_argument("--email", required=True)
    parser.add_argument("--expected-uid", help="Required for grant; use the UID reviewed in inspect output.")
    args = parser.parse_args()
    if args.action == "grant" and not args.expected_uid:
        parser.error("grant requires --expected-uid")
    try:
        import firebase_admin
        from firebase_admin import auth, credentials, firestore
    except ImportError:
        sys.exit("Install the official firebase-admin Python package in a trusted admin environment, then rerun. Do not put admin credentials in the iOS app.")
    app = firebase_admin.initialize_app(credentials.ApplicationDefault(), {"projectId": PROJECT_ID})
    try:
        user = auth.get_user_by_email(args.email, app=app)
        hospital = firestore.client(app=app).collection("hospitals").document(DEMO_HOSPITAL_ID).get()
        if not hospital.exists:
            raise ValueError("The demo hospital does not exist in this project. No access changed.")
        result = {
            "project": PROJECT_ID,
            "email": user.email,
            "uid": user.uid,
            "emailVerified": user.email_verified,
            "disabled": user.disabled,
            "currentRole": (user.custom_claims or {}).get("role", "patient"),
            "currentHospitalIDs": (user.custom_claims or {}).get("hospitalIDs", []),
            "requestedHospitalID": DEMO_HOSPITAL_ID,
        }
        if args.action == "inspect":
            print(json.dumps(result, indent=2))
            print("Read-only inspection. No account or hospital data changed.")
        else:
            claims = planned_claims(user, args.expected_uid)
            auth.set_custom_user_claims(user.uid, claims, app=app)
            updated = auth.get_user(user.uid, app=app)
            if updated.custom_claims != claims:
                raise RuntimeError("Staff claims could not be confirmed. Inspect the account before retrying.")
            print(json.dumps({**result, "assignedRole": "staff", "assignedHospitalIDs": [DEMO_HOSPITAL_ID]}, indent=2))
            print("Confirmed. In CardioSafe, use Refresh account to reload trusted access.")
    except Exception as error:
        sys.exit(f"Admin operation failed: {error}")
    finally:
        firebase_admin.delete_app(app)


if __name__ == "__main__":
    main()

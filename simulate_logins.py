"""
simulate_logins.py - log in N different students to test the auto-scaling trigger.

    python simulate_logins.py --url http://<your-ALB-DNS-name> --users 13
    python simulate_logins.py --url http://localhost:8000 --users 12 --logout     # 12 = just under the trigger

Uses the 40 generated accounts (student1 .. student40). The 13th distinct student pushes the
site over the threshold of 12. Plain Python 3, no extra packages.
"""
import argparse
import json
import time
import urllib.error
import urllib.request


def call(url, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url + path, data=data, headers={"Content-Type": "application/json"},
                                 method="POST" if body is not None else "GET")
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.load(resp)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://localhost:8000", help="site address (the ALB DNS name on AWS)")
    ap.add_argument("--users", type=int, default=13, help="how many different students to log in (1-40)")
    ap.add_argument("--logout", action="store_true", help="sign them all out again at the end")
    args = ap.parse_args()
    url = args.url.rstrip("/")

    sessions = []
    for i in range(1, min(args.users, 40) + 1):
        try:
            r = call(url, "/api/login", {"username": f"student{i}", "email": f"student{i}@retrograde-demo.com"})
            sessions.append(r["session_id"])
            print(f"login {i:>2}: ok")
        except urllib.error.HTTPError as e:
            print(f"login {i:>2}: FAILED ({e.code})")
        time.sleep(0.2)

    s = call(url, "/api/traffic-status")
    print(f"\n{s['status_message']}")
    print(f"active logins on the instance that answered: {s['active_logins']}  (threshold: more than {s['scale_threshold']})")
    print(f"answered by instance {s['instance_id']}  |  instances in service: {s['instance_count']}")
    print("\nWatch: CloudWatch -> Metrics -> Retrograde/Portal -> ActiveLogins, then the alarm, then EC2 -> Auto Scaling groups -> Activity.")

    if args.logout:
        for sid in sessions:
            call(url, "/api/session/logout", {"session_id": sid})
        print(f"\nsigned {len(sessions)} users out again")


if __name__ == "__main__":
    main()

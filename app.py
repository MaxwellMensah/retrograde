import asyncio
import logging
import os
import secrets
import socket
import threading
import time
import urllib.request
from contextlib import asynccontextmanager
from datetime import UTC, datetime

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from pydantic import BaseModel

log = logging.getLogger(
    "uvicorn.error"
)  # shows up in the normal uvicorn / systemd / CloudWatch-agent log

# ═══════════════════════════════════════════════════════════════════════════
# Scaling + AWS settings. Override any of these with environment variables
# ═══════════════════════════════════════════════════════════════════════════
SCALE_THRESHOLD = int(
    os.getenv("SCALE_THRESHOLD", "12")
)  # AWS trigger: MORE than 12 logged-in users (the 13th) scales out
SESSION_TTL_SECONDS = int(
    os.getenv("SESSION_TTL_SECONDS", "600")
)  # a login with no heartbeat for this long stops counting
CW_NAMESPACE = os.getenv(
    "CW_NAMESPACE", "Retrograde/Portal"
)  # CloudWatch namespace the metrics are published to
CW_PUBLISH = (
    os.getenv("CW_PUBLISH", "true").lower() == "true"
)  # set false on your laptop


def discover_instance() -> dict:
    """Which EC2 instance is this? Uses the instance metadata service (IMDSv2); off AWS it falls back to the hostname."""
    if os.getenv("INSTANCE_ID"):
        return {
            "instance_id": os.environ["INSTANCE_ID"],
            "availability_zone": os.getenv("AZ", ""),
        }
    base = "http://169.254.169.254/latest"
    try:
        req = urllib.request.Request(
            base + "/api/token",
            method="PUT",
            headers={"X-aws-ec2-metadata-token-ttl-seconds": "21600"},
        )
        token = urllib.request.urlopen(req, timeout=1).read().decode()

        def get(path: str) -> str:
            r = urllib.request.Request(
                base + "/meta-data/" + path, headers={"X-aws-ec2-metadata-token": token}
            )
            return urllib.request.urlopen(r, timeout=1).read().decode()

        return {
            "instance_id": get("instance-id"),
            "availability_zone": get("placement/availability-zone"),
        }
    except Exception:
        return {"instance_id": socket.gethostname(), "availability_zone": ""}


INSTANCE = discover_instance()


def aws_region():
    az = INSTANCE["availability_zone"]
    return (
        os.getenv("AWS_REGION")
        or os.getenv("AWS_DEFAULT_REGION")
        or (az[:-1] if az else None)
    )


def discover_asg_name(instance_id: str) -> str:
    """Automatically find the ASG name from AWS using the instance ID."""
    if not instance_id or instance_id.startswith("localhost") or not instance_id.startswith("i-"):
        return ""
    try:
        import boto3
        client = boto3.client("autoscaling", region_name=aws_region())
        response = client.describe_auto_scaling_instances(InstanceIds=[instance_id])
        asig = response.get("AutoScalingInstances", [])
        if asig:
            discovered = asig[0].get("AutoScalingGroupName", "")
            log.info("Auto-discovered ASG name: %s", discovered)
            return discovered
    except Exception as exc:
        log.warning("Could not auto-discover ASG name: %s", exc)
    return ""


# Initialize ASG Name via environment variable or auto-discovery
ASG_NAME = os.getenv("ASG_NAME", "")
if not ASG_NAME:
    ASG_NAME = discover_asg_name(INSTANCE.get("instance_id", ""))


# ═══════════════════════════════════════════════════════════════════════════
# In-memory traffic & active session tracking (this instance only)
# ═══════════════════════════════════════════════════════════════════════════
ACTIVE_LOGINS = set()  # student ids that currently have a live session
TOTAL_LOGIN_EVENTS = 0  # every successful login since this process started
_SESSIONS = {}  # session_id -> {"student_id": int, "last_seen": float}
_LOGINS_SINCE_PUBLISH = 0
_LOCK = threading.Lock()


def _expire_locked(now: float) -> None:
    cutoff = now - SESSION_TTL_SECONDS
    for sid in [s for s, v in _SESSIONS.items() if v["last_seen"] < cutoff]:
        del _SESSIONS[sid]
    _sync_active_locked()


def _sync_active_locked() -> None:
    ACTIVE_LOGINS.clear()
    ACTIVE_LOGINS.update(v["student_id"] for v in _SESSIONS.values())


def start_session(student_id: int) -> str:
    global TOTAL_LOGIN_EVENTS, _LOGINS_SINCE_PUBLISH
    session_id = secrets.token_urlsafe(16)
    with _LOCK:
        _expire_locked(time.time())
        _SESSIONS[session_id] = {"student_id": student_id, "last_seen": time.time()}
        _sync_active_locked()
        TOTAL_LOGIN_EVENTS += 1
        _LOGINS_SINCE_PUBLISH += 1
        active = len(ACTIVE_LOGINS)
    log.info(
        "LOGIN student_id=%s active_logins=%s total_logins=%s instance=%s",
        student_id,
        active,
        TOTAL_LOGIN_EVENTS,
        INSTANCE["instance_id"],
    )
    return session_id


def touch_session(session_id: str) -> bool:
    with _LOCK:
        entry = _SESSIONS.get(session_id)
        if not entry:
            return False
        entry["last_seen"] = time.time()
        return True


def end_session(session_id: str) -> bool:
    with _LOCK:
        entry = _SESSIONS.pop(session_id, None)
        _sync_active_locked()
        active = len(ACTIVE_LOGINS)
    if entry:
        log.info(
            "LOGOUT student_id=%s active_logins=%s instance=%s",
            entry["student_id"],
            active,
            INSTANCE["instance_id"],
        )
    return entry is not None


# ═══════════════════════════════════════════════════════════════════════════
# How many instances does the Auto Scaling Group have? (optional, cached)
# ═══════════════════════════════════════════════════════════════════════════
_fleet = {"at": 0.0, "value": None, "client": None}


def get_instance_count(max_age: float = 15.0):
    if not ASG_NAME:
        return None
    now = time.time()
    if now - _fleet["at"] < max_age:
        return _fleet["value"]
    value = None
    try:
        if _fleet["client"] is None:
            import boto3

            _fleet["client"] = boto3.client("autoscaling", region_name=aws_region())
        groups = _fleet["client"].describe_auto_scaling_groups(
            AutoScalingGroupNames=[ASG_NAME]
        )["AutoScalingGroups"]
        if groups:
            value = sum(
                1
                for i in groups[0]["Instances"]
                if i.get("LifecycleState") == "InService"
            )
    except Exception as exc:
        log.warning("could not read ASG size: %s", exc)
    _fleet.update(at=now, value=value)
    return value


# ═══════════════════════════════════════════════════════════════════════════
# CloudWatch publishing logic
# ═══════════════════════════════════════════════════════════════════════════
def build_metric_data(
    active: int, new_logins: int, instance_id: str, asg_name: str, stamp
) -> list:
    fleet_dims = [{"Name": "AutoScalingGroupName", "Value": asg_name or "unassigned"}]
    instance_dims = fleet_dims + [{"Name": "InstanceId", "Value": instance_id}]
    data = []
    for name, value in (("ActiveLogins", active), ("LoginEvents", new_logins)):
        for dims in (fleet_dims, instance_dims):
            data.append(
                {
                    "MetricName": name,
                    "Dimensions": dims,
                    "Timestamp": stamp,
                    "Value": float(value),
                    "Unit": "Count",
                }
            )
    return data


def publish_once(client, stamp=None) -> list:
    global _LOGINS_SINCE_PUBLISH
    stamp = stamp or datetime.now(UTC).replace(second=0, microsecond=0)
    with _LOCK:
        _expire_locked(time.time())
        active, new_logins = len(ACTIVE_LOGINS), _LOGINS_SINCE_PUBLISH
        _LOGINS_SINCE_PUBLISH = 0
    data = build_metric_data(
        active, new_logins, INSTANCE["instance_id"], ASG_NAME, stamp
    )
    try:
        client.put_metric_data(Namespace=CW_NAMESPACE, MetricData=data)
    except Exception:
        with _LOCK:
            _LOGINS_SINCE_PUBLISH += new_logins  # keep the count for the next try
        raise
    log.info(
        "CloudWatch <- active_logins=%s new_logins=%s instance=%s",
        active,
        new_logins,
        INSTANCE["instance_id"],
    )
    return data


async def publish_loop() -> None:
    import boto3

    client = boto3.client("cloudwatch", region_name=aws_region())
    while True:
        await asyncio.sleep(61 - (time.time() % 60))
        try:
            await asyncio.to_thread(publish_once, client)
        except Exception:
            log.exception("CloudWatch publish failed (will retry next minute)")


@asynccontextmanager
async def lifespan(app: FastAPI):
    task = None
    log.info(
        "Retrograde backend up on instance %s (%s) | scale threshold: more than %s logins | ASG: %s",
        INSTANCE["instance_id"],
        INSTANCE["availability_zone"] or "no AZ",
        SCALE_THRESHOLD,
        ASG_NAME or "not set",
    )
    if CW_PUBLISH:
        try:
            import boto3  # noqa: F401

            task = asyncio.create_task(publish_loop())
        except ImportError:
            log.warning(
                "boto3 is not installed - CloudWatch publishing is OFF (pip install boto3)"
            )
    else:
        log.info("CW_PUBLISH=false - counts stay local (see /api/traffic-status)")
    yield
    if task:
        task.cancel()


app = FastAPI(title="Project Retrograde - Grading Checker", lifespan=lifespan)

# Mount static folder and templates
app.mount("/static", StaticFiles(directory="static"), name="static")
app.mount("/images", StaticFiles(directory="images"), name="images")
templates = Jinja2Templates(directory="templates")

# 1. Automatically generate 40 class student profiles + custom demo accounts
STUDENTS_DB = []

for i in range(1, 41):
    username = f"student{i}"
    email = f"student{i}@retrograde-demo.com"
    full_name = f"Class Student {i}"
    roll_no = f"RETRO-2026-{i:03d}"

    modules = {
        "Linux": {"raw_score": 70 + (i * 3) % 25, "weight": 0.15},
        "Networking & Security": {"raw_score": 65 + (i * 4) % 30, "weight": 0.15},
        "AWS Cloud Services": {"raw_score": 75 + (i * 2) % 20, "weight": 0.25},
        "Terraform for IaC": {"raw_score": 60 + (i * 5) % 35, "weight": 0.20},
        "AI Fundamentals": {"raw_score": 68 + (i * 3) % 28, "weight": 0.10},
        "Database Management": {"raw_score": 72 + (i * 2) % 25, "weight": 0.15},
    }

    STUDENTS_DB.append(
        {
            "id": i,
            "username": username,
            "email": email,
            "full_name": full_name,
            "roll_no": roll_no,
            "gender": "M" if i % 2 else "F",
            "modules": modules,
        }
    )

# Add custom presentation actors
STUDENTS_DB.extend(
    [
        {
            "id": 101,
            "username": "maxwell",
            "email": "maxwell@gmail.com",
            "full_name": "Maxwell O.",
            "roll_no": "RETRO-2026-101",
            "gender": "M",
            "modules": {
                "Linux": {"raw_score": 88, "weight": 0.15},
                "Networking & Security": {"raw_score": 75, "weight": 0.15},
                "AWS Cloud Services": {"raw_score": 90, "weight": 0.25},
                "Terraform for IaC": {"raw_score": 82, "weight": 0.20},
                "AI Fundamentals": {"raw_score": 78, "weight": 0.10},
                "Database Management": {"raw_score": 85, "weight": 0.15},
            },
        },
        {
            "id": 102,
            "username": "esther",
            "email": "esther@gmail.com",
            "full_name": "Esther K.",
            "roll_no": "RETRO-2026-102",
            "gender": "F",
            "modules": {
                "Linux": {"raw_score": 92, "weight": 0.15},
                "Networking & Security": {"raw_score": 85, "weight": 0.15},
                "AWS Cloud Services": {"raw_score": 95, "weight": 0.25},
                "Terraform for IaC": {"raw_score": 88, "weight": 0.20},
                "AI Fundamentals": {"raw_score": 80, "weight": 0.10},
                "Database Management": {"raw_score": 90, "weight": 0.15},
            },
        },
    ]
)

NEW_MEMBERS = [
    ("angela.adu@azubiafrica.org", "angela", "F"),
    ("augustus.doku@azubiafrica.org", "augustus", "M"),
    ("ayaw.ganiu@azubiafrica.org", "ayaw", "M"),
    ("bismark.hayford@azubiafrica.org", "bismark", "M"),
    ("bright.antie@azubiafrica.org", "bright", "M"),
    ("daniel.mensah@azubiafrica.org", "daniel", "M"),
    ("dorcas.sai@azubiafrica.org", "dorcas", "F"),
    ("elikem.sandra@azubiafrica.org", "elikem", "F"),
    ("emmanuel.larbi@azubiafrica.org", "emmanuel", "M"),
    ("emmanuel.koranteng@azubiafrica.org", "emmanuel", "M"),
    ("emmanuel.donkor@azubiafrica.org", "emmanuel", "M"),
    ("esther.aidam@azubiafrica.org", "esther", "F"),
    ("esther.appiah@azubiafrica.org", "esther", "F"),
    ("faustina.anapey@azubiafrica.org", "faustina", "F"),
    ("grace.boadi@azubiafrica.org", "grace", "F"),
    ("harold.amarquaye@azubiafrica.org", "harold", "M"),
    ("henry.amoah@azubiafrica.org", "henry", "M"),
    ("jason.osei@azubiafrica.org", "jason", "M"),
    ("jonathan.annan@azubiafrica.org", "jonathan", "M"),
    ("jonathan.banful@azubiafrica.org", "jonathan", "M"),
    ("joshua.yalleh@azubiafrica.org", "joshua", "M"),
    ("kevin.tsikudo@azubiafrica.org", "kevin", "M"),
    ("kwaku.osei@azubiafrica.org", "kwaku", "M"),
    ("matilda.annan@azubiafrica.org", "matilda", "F"),
    ("maxwell.mensah@azubiafrica.org", "maxwell", "M"),
    ("michael.asimeng@azubiafrica.org", "michael", "M"),
    ("michael.awuah@azubiafrica.org", "michael", "M"),
    ("moses.kweku@azubiafrica.org", "moses", "M"),
    ("parker.asante@azubiafrica.org", "parker", "M"),
    ("philip.wemegah@azubiafrica.org", "philip", "M"),
    ("philipa.darkwah@azubiafrica.org", "philipa", "F"),
    ("prince.asante@azubiafrica.org", "prince", "M"),
    ("priscilla.dadzie@azubiafrica.org", "priscilla", "F"),
    ("prosper.dokli@azubiafrica.org", "prosper", "M"),
    ("richmond.annan@azubiafrica.org", "richmond", "M"),
    ("richmond.nkrumah@azubiafrica.org", "richmond", "M"),
    ("robert.deku@azubiafrica.org", "robert", "M"),
    ("sabaina.adoblanui@azubiafrica.org", "sabaina", "F"),
    ("shadrack.kwaw@azubiafrica.org", "shadrack", "M"),
    ("sharon.dededzi@azubiafrica.org", "sharon", "F"),
    ("theophilus.nuworku@azubiafrica.org", "theophilus", "M"),
    ("winfred.ashie@azubiafrica.org", "winfred", "M"),
    ("wuntia.yakubu@azubiafrica.org", "wuntia", "F"),
    ("yasmine.azumah@azubiafrica.org", "yasmine", "F"),
    ("brian.mathenge@azubiafrica.org", "brian", "M"),
    ("william.mukoyani@azubiafrica.org", "william", "M"),
]

start_id = 103

for idx, (email, username, gender) in enumerate(NEW_MEMBERS, start=start_id):
    first, last = email.split("@")[0].split(".", 1)

    modules = {
        "Linux": {"raw_score": 70 + (idx * 3) % 25, "weight": 0.15},
        "Networking & Security": {"raw_score": 65 + (idx * 4) % 30, "weight": 0.15},
        "AWS Cloud Services": {"raw_score": 75 + (idx * 2) % 20, "weight": 0.25},
        "Terraform for IaC": {"raw_score": 60 + (idx * 5) % 35, "weight": 0.20},
        "AI Fundamentals": {"raw_score": 68 + (idx * 3) % 28, "weight": 0.10},
        "Database Management": {"raw_score": 72 + (idx * 2) % 25, "weight": 0.15},
    }

    STUDENTS_DB.append(
        {
            "id": idx,
            "username": username,
            "email": email,
            "full_name": f"{first.title()} {last.title()}",
            "roll_no": f"RETRO-2026-{idx:03d}",
            "gender": gender,
            "modules": modules,
        }
    )


def get_grade(score: int):
    if score >= 85:
        return {"grade": "Distinction", "remark": "Exceptional Mastery"}
    elif score >= 75:
        return {"grade": "A1", "remark": "Excellent"}
    elif score >= 70:
        return {"grade": "B2", "remark": "Very Good"}
    elif score >= 65:
        return {"grade": "B3", "remark": "Good"}
    elif score >= 60:
        return {"grade": "C4", "remark": "Credit"}
    elif score >= 55:
        return {"grade": "C5", "remark": "Credit"}
    elif score >= 50:
        return {"grade": "C6", "remark": "Credit"}
    else:
        return {"grade": "F9", "remark": "Needs Remediation"}


class LoginPayload(BaseModel):
    username: str
    email: str


class SessionPayload(BaseModel):
    session_id: str


@app.get("/", response_class=HTMLResponse)
def serve_frontend(request: Request):
    return templates.TemplateResponse(request, "index.html", {})


@app.post("/api/login")
def login(payload: LoginPayload):
    username = payload.username.strip().lower()
    email = payload.email.strip().lower()

    student = next(
        (s for s in STUDENTS_DB if s["username"] == username and s["email"] == email),
        None,
    )
    if not student:
        raise HTTPException(
            status_code=401, detail="Invalid username or email address."
        )

    session_id = start_session(student["id"])

    return {
        "success": True,
        "student_id": student["id"],
        "message": "Login successful",
        "session_id": session_id,
    }


@app.post("/api/session/heartbeat")
def session_heartbeat(payload: SessionPayload):
    return {"ok": touch_session(payload.session_id)}


@app.post("/api/session/logout")
def session_logout(payload: SessionPayload):
    return {"ok": end_session(payload.session_id)}


@app.get("/api/grades/{student_id}")
def get_student_grades(student_id: int):
    student = next((s for s in STUDENTS_DB if s["id"] == student_id), None)
    if not student:
        raise HTTPException(status_code=404, detail="Student record not found.")

    weighted_sum = 0.0
    evaluated_modules = []

    for mod_name, data in student["modules"].items():
        score = data["raw_score"]
        weight = data["weight"]
        grade_info = get_grade(score)

        weighted_sum += score * weight
        evaluated_modules.append(
            {
                "subject": mod_name,
                "score": score,
                "weight_pct": int(weight * 100),
                "grade": grade_info["grade"],
                "remark": grade_info["remark"],
            }
        )

    final_cumulative_score = round(weighted_sum, 1)
    final_grade_info = get_grade(int(final_cumulative_score))
    gpa_equivalent = round((final_cumulative_score / 100) * 4.0, 2)

    return {
        "full_name": student["full_name"],
        "roll_no": student["roll_no"],
        "gender": student["gender"],
        "subjects": evaluated_modules,
        "cumulative_average": final_cumulative_score,
        "overall_grade": final_grade_info["grade"],
        "overall_remark": final_grade_info["remark"],
        "gpa": gpa_equivalent,
    }


@app.get("/api/traffic-status")
def traffic_status():
    with _LOCK:
        _expire_locked(time.time())
        active_count = len(ACTIVE_LOGINS)
    fleet = get_instance_count()
    triggered = active_count > SCALE_THRESHOLD
    scaled_up = triggered or (fleet or 1) > 1
    if (fleet or 1) > 1:
        message = f"🚀 Scaled Up (ASG Active · {fleet} Instances)"
    elif triggered:
        message = "🚀 Scaling Triggered (ASG launching)"
    else:
        message = f" Normal Capacity ({fleet or 1} Instance{'s' if (fleet or 1) != 1 else ''})"
    return {
        "active_logins": active_count,
        "total_events": TOTAL_LOGIN_EVENTS,
        "scaled_up": scaled_up,
        "status_message": message,
        "instance_id": INSTANCE["instance_id"],
        "availability_zone": INSTANCE["availability_zone"],
        "instance_count": fleet,
        "scale_threshold": SCALE_THRESHOLD,
    }


@app.get("/health")
def health_check():
    return {"status": "healthy", "instance_id": INSTANCE["instance_id"]}
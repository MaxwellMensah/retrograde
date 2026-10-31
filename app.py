from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from pydantic import BaseModel

app = FastAPI(title="ProjectRetro - Grading Checker")

# Setup template rendering for your 3-page frontend
templates = Jinja2Templates(directory="templates")

# In-memory traffic & active session tracking for the live demo
ACTIVE_LOGINS = set()
TOTAL_LOGIN_EVENTS = 0

# 1. Automatically generate 40 class student profiles + custom demo accounts
STUDENTS_DB = []

for i in range(1, 41):
    username = f"student{i}"
    email = f"student{i}@retrograde-demo.com"
    full_name = f"Class Student {i}"
    roll_no = f"RETRO-2026-{i:03d}"

    # Curriculum module scores with realistic weights
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
            "modules": modules,
        }
    )

# Add your custom presentation actors for initial testing
STUDENTS_DB.extend(
    [
        {
            "id": 101,
            "username": "maxwell",
            "email": "maxwell@gmail.com",
            "full_name": "Maxwell O.",
            "roll_no": "RETRO-2026-101",
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


# 2. Bug-free integer boundary grading function
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


# 3. Route to serve the frontend UI
# @app.get("/", response_class=HTMLResponse)
# def serve_frontend(request: Request):
#     return templates.TemplateResponse("index.html", {"request": request})

# 3. Route to serve the 3-page UI
@app.get("/", response_class=HTMLResponse)
def serve_frontend(request: Request):
    return templates.TemplateResponse(request, "retro_test.html", {})


# 4. Login Endpoint (Triggers traffic counter)
@app.post("/api/login")
def login(payload: LoginPayload):
    global TOTAL_LOGIN_EVENTS
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

    ACTIVE_LOGINS.add(student["id"])
    TOTAL_LOGIN_EVENTS += 1

    return {"success": True, "student_id": student["id"], "message": "Login successful"}


# 5. Private Grades & Weighted Aggregation Endpoint
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
        "subjects": evaluated_modules,
        "cumulative_average": final_cumulative_score,
        "overall_grade": final_grade_info["grade"],
        "overall_remark": final_grade_info["remark"],
        "gpa": gpa_equivalent,
    }


# 6. Traffic Status Endpoint (Polled by frontend every 3s)
@app.get("/api/traffic-status")
def traffic_status():
    active_count = len(ACTIVE_LOGINS)
    scaled_up = active_count >= 10
    return {
        "active_logins": active_count,
        "total_events": TOTAL_LOGIN_EVENTS,
        "scaled_up": scaled_up,
        "status_message": "🚀 Scaled Up (ASG Active)"
        if scaled_up
        else "🟢 Normal Capacity (1 Instance)",
    }


# 7. ALB Health Check Endpoint
@app.get("/health")
def health_check():
    return {"status": "healthy"}

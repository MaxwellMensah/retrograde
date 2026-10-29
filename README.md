```markdown
# 🎓 Project #Retrograde — Academic Performance Portal

A high-availability candidate performance verification and grading portal engineered with **FastAPI**, **Tailwind CSS**, and modern Apple-style liquid-glass UI components.

---

## 🚀 Key Features

* **Authenticated Transcripts:** Secure login portal verifying candidate credentials and rendering dynamic grade averages, GPA calculations, and letter grade breakdowns.
* **Weighted Engineering Curriculum:** Deterministic scoring across 6 key modules:
  * AWS Cloud Services (25%)
  * Terraform IaC (20%)
  * Linux Administration (15%)
  * Networking & Security (15%)
  * Database Essentials (15%)
  * AI Fundamentals (10%)
* **Live Infrastructure Traffic Polling:** Real-time auto-scaling status monitoring ticker built into the header badge.
* **Welcome Centre AI Assistant:** Interactive floating agent ready to answer visitor questions and assist with demo accounts.

---

## 📁 Repository Structure

```text
retrograde/
├── retrograde/
│   ├── templates/
│   │   └── index.html      # Main frontend portal template (Tailwind & Glassmorphism)
│   ├── app.py              # FastAPI backend server & API routing
│   └── requirements.txt    # Python package dependencies
├── .gitignore
├── LICENSE
└── README.md

```

---

## 🛠️ Getting Started & Local Installation

### 1. Clone the Repository

```bash
git clone [https://github.com/MaxwellMensah/retrograde.git](https://github.com/MaxwellMensah/retrograde.git)
cd retrograde

```

### 2. Install Dependencies

Make sure you have Python installed, then install the required packages:

```bash
pip install -r retrograde/requirements.txt

```

### 3. Run the Application

Start the FastAPI backend server using Uvicorn:

```bash
uvicorn retrograde.app:app --reload --port 8000

```

Open your browser and navigate to: **`http://localhost:8000`**

---

## 👥 Presentation Demo Accounts

You can use the following quick-test credentials on the sign-in page:

* **Candidate 1:** `maxwell` / `maxwell@gmail.com`
* **Candidate 2:** `esther` / `esther@gmail.com`
* **Candidate 3:** `student1` / `student1@retrograde-demo.com`

---

## 📄 License

Distributed under the **MIT License**. See `LICENSE` for more information.
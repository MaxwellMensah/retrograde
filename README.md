# Retrograde - Academic Performance Portal

A high-availability candidate performance verification and grading portal, engineered with **FastAPI**,
**Tailwind CSS** and an Apple-style liquid-glass interface. It runs on **AWS** behind a load balancer and
**scales itself out automatically when more than 12 candidates are signed in at the same time**. The whole
AWS environment is built from code with **Terraform**: one command to create it, one to remove it.

---

## Contents

1. [The big picture](#-the-big-picture)
2. [Key features](#-key-features)
3. [What's new](#-whats-new)
4. [Repository structure](#-repository-structure)
5. [How the application works](#-how-the-application-works)
6. [How the app tells AWS it is busy](#-how-the-app-tells-aws-it-is-busy)
7. [AWS services: what each does and why we need it](#-aws-services-what-each-does-and-why-we-need-it)
8. [Terraform: building it all with one command](#-terraform-building-it-all-with-one-command)
9. [The service lifecycle, phase by phase](#-the-service-lifecycle-phase-by-phase)
10. [Local development](#-local-development)
11. [Configuration reference](#-configuration-reference)
12. [Demo accounts](#-presentation-demo-accounts)
13. [Troubleshooting](#-troubleshooting)
14. [Security notes and known limits](#-security-notes-and-known-limits)
15. [License](#-license)

---

## 🧭 The big picture

Think of the portal as a **restaurant**. Every AWS service has a job a restaurant also has to do:

| In the restaurant | In AWS | Its job |
|---|---|---|
| The host at the front door | **Application Load Balancer (ALB)** | One public address. Seats each guest at a table that is open and healthy. |
| Tables and waiters | **EC2 instances** running `app.py` | Actually serve the candidates. |
| The manager who opens extra tables | **Auto Scaling Group (ASG)** | Adds or removes instances so there are always enough. |
| Someone counting guests at the door | **CloudWatch metric** `ActiveLogins` | The number the manager watches. |
| A bell that rings when it gets too busy | **CloudWatch alarm** | Fires when more than 12 users are signed in. |
| The manager's standing order | **Scaling policy** | "When the bell rings, run 2 tables (or 3)." |
| A recipe book copied to every new kitchen | **S3 bucket** | Every new instance downloads the same app code. |
| Staff badges | **IAM role** | Lets instances read S3 and report to CloudWatch, nothing more. |
| Locked doors | **Security groups** | Only the host can reach the kitchen. |
| The architect's blueprint and the builder | **Terraform** | Builds all of the above from code, identically every time. |

### Architecture

```
                         ┌───────────────────────────────────┐
  Candidate's browser ──▶│     Application Load Balancer     │   port 80 · health check /health
                         │   (one public DNS address)        │   sticky sessions (cookie)
                         └─────────────────┬─────────────────┘
                   ┌───────────────────────┼───────────────────────┐
                   ▼                       ▼                       ▼
            ┌─────────────┐         ┌─────────────┐         ┌─────────────┐
            │  EC2  #1    │         │  EC2  #2    │         │  EC2  #3    │   ◀── Auto Scaling Group
            │  FastAPI    │         │  added at   │         │  added at   │       min 1 · max 3
            │  :8000      │         │  13 users   │         │  24 users   │
            └──────┬──────┘         └─────────────┘         └─────────────┘
                   │  once a minute: "how many users are signed in on me?"
                   ▼
        ┌───────────────────────────────────┐
        │  CloudWatch metric ActiveLogins   │   namespace  Retrograde/Portal
        │  (every instance adds its count)  │   Sum = users signed in across the whole fleet
        └─────────────────┬─────────────────┘
                          │  is the Sum greater than 12 ?
                          ▼
        ┌───────────────────────────────────┐      ┌──────────────────────┐
        │        CloudWatch alarm           │─────▶│    Scaling policy    │──▶  "run 2 instances"
        └───────────────────────────────────┘      └──────────────────────┘      (3 at 24+ users)

   Set up once by Terraform ─▶  S3 bucket (app code) · IAM role · security groups · all of the above
```

An **ALB only spreads traffic**. It never adds servers. The thing that adds servers is the **Auto Scaling
Group**, and it only acts when a **CloudWatch alarm** tells it to. The app supplies the number that alarm
watches (the count of signed-in users), because AWS cannot see logins on its own.

---

## 🚀 Key features

* **Authenticated Transcripts:** secure sign-in that renders each candidate's weighted score, grade, GPA
  and a per-module breakdown with score bars.
* **Weighted Engineering Curriculum:** deterministic scoring across 6 modules:
  * AWS Cloud Services (25%)
  * Terraform IaC (20%)
  * Linux Administration (15%)
  * Networking & Security (15%)
  * Database Essentials (15%)
  * AI Fundamentals (10%)
* **Live infrastructure status:** a header badge polls the backend every 3 seconds and shows capacity
  ("Normal Capacity", "Scaling Triggered", "Scaled Up"), plus which instance served you.
* **Auto-scaling on real usage:** the 13th concurrent sign-in triggers AWS to add instances.
* **Thinkibot, the Welcome Centre assistant:** answers sign-in, module weight, grading, auto-scaling and
  contact questions, and can report live server numbers.
* **About & Contact page:** alumni hero, project overview, the seven RETROGRADE executives, contact grid
  (X, Facebook, phone, email), and a Google Map with directions.
* **Infrastructure as code:** the entire AWS environment is one `terraform apply`.

---

## ✨ What's new

| Area | Update |
|---|---|
| **Interface** | Apple-style tiled layout on a white page; liquid-glass header, panels and cards; Helvetica Neue type; fully responsive with a glass menu for phones and tablets. |
| **Home page** | Vibrant hero, world-map metrics tile, campus gallery, curriculum cards, dark accreditation ticker, dark footer. |
| **Results page** | A focused, signed-in view (the landing menu is hidden), clear watery glass on a neutral background, larger type, outlined score bars, and a **profile picture chosen by gender** (M shows Shrek, F shows Fiona). |
| **About & Contact** | New page with alumni photo, executives, contact details and a Google Map. |
| **Thinkibot** | The assistant now understands what you ask instead of giving one canned answer. |
| **Backend** | Real login sessions (heartbeat and sign-out), a `gender` field, instance details in the status API, and a CloudWatch publisher for `ActiveLogins`. |
| **Infrastructure** | Terraform builds the ALB, Auto Scaling Group, S3 bundle, IAM, alarms and scaling policies in one go. |
| **Delivery** | Tailwind CSS is compiled into the page (no CDN warning); GitHub Actions validates the Python and Terraform. |

---

## 📁 Repository structure

```text
retrograde/
├── .github/workflows/     # CI: validates the Python and the Terraform on every push / pull request
├── templates/
│   └── index.html    # the whole frontend: home, sign-in, results, About & Contact (served by FastAPI)
├── terraform/             # infrastructure as code: one `apply` builds the AWS environment
│   ├── main.tf            #   every AWS resource
│   ├── variables.tf       #   the settings you can change
│   ├── outputs.tf         #   prints the site URL and the demo commands
│   └── user_data.sh.tpl   #   boot script every new server runs
├── app.py                 # FastAPI backend: login, grades, session tracking, CloudWatch publisher
├── simulate_logins.py     # logs in N students at once to trigger scaling on demand
├── requirements.txt       # fastapi, uvicorn, jinja2, boto3
├── AWS_SETUP.md           # the same AWS setup done by hand with the CLI (learning / fallback)
├── LICENSE
└── README.md
```

---

## 🧩 How the application works

### Frontend

One page (`templates/index.html`) switches between four views without reloading:

| View | What it shows |
|---|---|
| **Home** | Hero, live metrics, campus life, weighted curriculum, accreditation badges. |
| **Sign In** | Candidate login (username + Azubi email). |
| **Results** | The candidate's transcript. The main menu is hidden here; **Sign Out** returns to Home. |
| **About & Contact** | Project overview, executives, contact details, map. |

Contact details and the executives list are placeholders held in one clearly marked block near the end of
the page's script (`CONTACT` and `EXECUTIVES`). Edit them there.

### Backend API

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/` | Serves the page. |
| `POST` | `/api/login` | Checks credentials, starts a tracked session, returns `student_id` and `session_id`. |
| `POST` | `/api/session/heartbeat` | The page calls this every 30 s while signed in, so the session stays "active". |
| `POST` | `/api/session/logout` | Ends the session (Sign Out or closing the tab). |
| `GET` | `/api/grades/{student_id}` | Weighted score, grade, GPA, per-module results and `gender`. |
| `GET` | `/api/traffic-status` | Active logins, instance id and zone, instance count, scaling status. Polled by the header badge. |
| `GET` | `/health` | Load balancer health check. Returns `200`. |

### Grading

Final score = the sum of each module score x its weight. GPA = final score / 100 x 4.0.

| Score | Grade | Remark |
|---|---|---|
| 85+ | Distinction | Exceptional Mastery |
| 75-84 | A1 | Excellent |
| 70-74 | B2 | Very Good |
| 65-69 | B3 | Good |
| 60-64 / 55-59 / 50-54 | C4 / C5 / C6 | Credit |
| below 50 | F9 | Needs Remediation |

### Signing in

Candidates sign in with their **Azubi email** and a **username that is the first name from that email**
(an email starting with `esther` means the username is `esther`). Capital letters do not matter.

---

## 📡 How the app tells AWS it is busy

AWS can see CPU and network, but it has no idea how many candidates are signed in. So the app counts them and
reports the number itself.

```
 Browser                        ALB                     EC2 (FastAPI)
    │  POST /api/login ──────────▶│─────────────────────────▶│  check credentials → start a session
    │◀────────── { student_id, session_id } ──────────────────│
    │  GET /api/grades/101 ──────▶│─────────────────────────▶│  weighted score, grade, GPA, gender
    │  every 30 s: heartbeat ────▶│─────────────────────────▶│  "still here"
    │  Sign Out / tab closed ────▶│─────────────────────────▶│  session removed
                                                             │
                                  once a minute (at second :01)
                                                             ▼
                                              CloudWatch  ActiveLogins = N
```

* **What counts as a login:** distinct students with a live session. The same student signing in twice counts
  once. A session ends on sign-out, when the tab closes, or after 10 minutes with no heartbeat.
* **Two metrics are published** (namespace `Retrograde/Portal`):

  | Metric | Meaning |
  |---|---|
  | `ActiveLogins` | Users currently signed in on this instance. **The alarm watches this.** |
  | `LoginEvents` | New logins since the last report (always safe to add up). |

  Each is published twice: once for the whole Auto Scaling Group (`AutoScalingGroupName`) and once for the
  individual instance (`+ InstanceId`) for dashboards.
* **Why `Sum`:** every instance writes its own count into the group-wide series, so the **Sum is the number of
  users signed in across the whole fleet**.
* **Why once a minute, at second :01:** it guarantees exactly one data point per instance per minute, so the
  Sum is never double counted.
* **Why stickiness is on:** each instance only counts users signed in *on it*. The load balancer cookie keeps
  one user on one instance, so nobody is counted twice.
* **The threshold:** the alarm fires when the Sum is **greater than 12**, so the **13th** sign-in triggers it.

---

## ☁️ AWS services: what each does and why we need it

| Service | What it does here | Why we need it | Terraform resource |
|---|---|---|---|
| **VPC and subnets** (existing) | The private network the system lives in, spread over at least 2 Availability Zones. | A load balancer needs two zones, so one zone failing does not take the site down. | `aws_vpc`, `aws_subnets` (looked up, not created) |
| **S3** | A private bucket holding `app.py` and the page. | Every new instance, including ones created automatically at scale-out time, fetches identical code with no manual copying. Keeps the server image generic. | `aws_s3_bucket`, `aws_s3_object` |
| **IAM role + instance profile** | Gives each server three permissions: read the app bundle from S3, publish to the `Retrograde/Portal` namespace, read the Auto Scaling Group size. | Servers act with no stored passwords, and can do only what they need (least privilege). | `aws_iam_role`, `aws_iam_role_policy`, `aws_iam_instance_profile` |
| **Systems Manager (Session Manager)** | Opens a shell on a server from the AWS console. | Debugging without SSH keys or an open port 22. | `AmazonSSMManagedInstanceCore` policy on the role |
| **Security groups** | Firewall rules: the internet reaches the ALB on port 80; only the ALB reaches the app on port 8000. | The servers are never directly exposed. | `aws_security_group` (x2) |
| **Application Load Balancer** | A single public address that spreads requests across healthy servers. | A stable entry point while servers come and go; removes failing servers; sticky sessions. | `aws_lb`, `aws_lb_listener` |
| **Target group** | The list of servers the ALB sends to, plus the `/health` check. | The ALB needs to know which servers are alive (healthy twice in a row, 15 s apart). | `aws_lb_target_group` |
| **Launch template** | The blueprint for every server: image, size, role, network, boot script. | Scaling needs a repeatable recipe for "one more server". | `aws_launch_template` |
| **EC2** (Amazon Linux 2023, `t3.micro`) | Runs FastAPI on port 8000 as a `systemd` service. | The compute that serves the portal. | created by the Auto Scaling Group |
| **Auto Scaling Group** | Keeps 1 to 3 servers running, replaces unhealthy ones, registers new ones with the load balancer. | The thing that actually adds and removes servers. | `aws_autoscaling_group` |
| **CloudWatch metric** | `ActiveLogins`, published by the app every minute. | Scaling on signed-in users is exact and demonstrable. CPU would barely move for 13 logins. | published by `app.py` |
| **CloudWatch alarm** | Watches `Sum(ActiveLogins) > 12` (scale out) and `< 8` for 5 minutes (scale in). | AWS needs an alarm to know when to act. | `aws_cloudwatch_metric_alarm` (x2) |
| **Scaling policy** | Step scaling to an exact size: 13-23 users run 2 servers; 24 or more run 3; below 8 returns to 1. | Turns the alarm into an action. Exact sizes avoid endless growth. | `aws_autoscaling_policy` (x2) |
| **Terraform** | Describes all of the above as code. | Reproducible, previewable (`plan`) and removable (`destroy`) environments. | the whole `terraform/` folder |
| **GitHub Actions** | Validates the Python and Terraform on every push. | Catches mistakes before they reach AWS. | `.github/workflows/` |

---

## 🏗️ Terraform: building it all with one command

Terraform reads the `.tf` files and creates, in the right order, everything in the table above. It also
records what it built in a **state file** (`terraform.tfstate`) so it can later change or remove exactly those
resources.

### Prerequisites

| Need | Check |
|---|---|
| An AWS account and credentials | `aws sts get-caller-identity` prints your account |
| Terraform 1.5 or newer | `terraform version` |
| An existing VPC tagged `Name = mygroupvpc` with **public** subnets in at least 2 zones | or pass `-var 'subnet_ids=["subnet-aaa","subnet-bbb"]'` |
| The latest `app.py` and `templates/index.html` in the repo root | Terraform uploads them to S3 |
| Python 3 (only for the `simulate_logins.py` demo script) | `python3 --version` |

### Quick start

```bash
cd terraform
terraform init       # downloads the AWS provider
terraform plan       # preview: about 20 resources to add, nothing else
terraform apply      # type yes · about 5-8 minutes
terraform output     # the site URL and the two demo commands
```

`apply` waits until the first server is healthy behind the load balancer, so when it finishes the site is
live at the printed URL.

### What `apply` builds, in order

```
terraform apply
   │
   ├─ 1  Look up ──────────  your VPC and subnets · the latest Amazon Linux 2023 image
   ├─ 2  S3 ───────────────  private bucket · upload app.py and the page
   ├─ 3  IAM ──────────────  role + instance profile (S3 read · CloudWatch publish · ASG read · SSM)
   ├─ 4  Security groups ──  alb-sg (80 from the internet) · web-sg (8000 from alb-sg only)
   ├─ 5  Load balancer ────  ALB · target group (/health, stickiness) · listener on port 80
   ├─ 6  Compute ──────────  launch template · Auto Scaling Group     ◀── waits for 1 healthy server
   └─ 7  Scaling ──────────  scale-out policy + alarm · scale-in policy + alarm
```

### What each new server does when it boots

The launch template's boot script (`user_data.sh.tpl`) runs once per server:

```
 1. install Python 3.11
 2. download app.py and the page from the S3 bucket
 3. pip install fastapi uvicorn jinja2 boto3
 4. write /etc/retrograde.env   (ASG_NAME, SCALE_THRESHOLD, AWS_REGION, CW_PUBLISH)
 5. register and start the systemd service  →  uvicorn on 0.0.0.0:8000, restarts if it crashes
```
Its log is `/var/log/retrograde-bootstrap.log`.

### Settings you can change (`terraform/variables.tf`)

| Variable | Default | Meaning |
|---|---|---|
| `region` | `us-east-1` | AWS region |
| `vpc_name` | `mygroupvpc` | Name tag of the existing VPC |
| `subnet_ids` | `[]` | Leave empty to auto-pick one subnet per zone |
| `name_prefix` | `retrograde` | Prefix for resource names |
| `asg_name` | `retrograde-asg` | Auto Scaling Group name (also the metric dimension) |
| `instance_type` | `t3.micro` | Server size |
| `min_size` / `max_size` | `1` / `3` | Fleet limits (the policy needs a max of 3 or more) |
| `login_threshold` | `12` | Scale out when more than this many users are signed in |
| `enable_scale_in` / `scale_in_threshold` | `true` / `8` | Scale back down after 5 minutes below this |
| `instance_profile_name` | `""` | Only if your account forbids creating IAM roles: use an existing profile |
| `allowed_cidr` | `0.0.0.0/0` | Who may open the site |
| `app_dir` | `""` | Folder with `app.py`; empty means the repo root |

Example: `terraform apply -var login_threshold=5 -var max_size=4`

### Changing the code after the first deploy

```bash
cd terraform
terraform apply      # re-uploads the changed files and creates a new launch template version

# running servers keep the old code until replaced:
aws autoscaling start-instance-refresh --auto-scaling-group-name retrograde-asg \
  --preferences '{"MinHealthyPercentage":0,"InstanceWarmup":120}'
```

### Removing everything

```bash
terraform destroy    # type yes · about 3-5 minutes · also deletes the S3 bucket
```
The load balancer and servers are billed by the hour while they exist (a few cents per hour), so always
destroy when you are done. Keep `terraform.tfstate` and `.terraform/` until after `destroy`, and never commit
them.

---

## 🔄 The service lifecycle, phase by phase

| Phase | What happens | AWS services involved | Why it matters |
|---|---|---|---|
| **0. Prepare** | Install Terraform and the AWS CLI, check credentials, confirm the VPC. | IAM (your own user), VPC | Terraform acts as you; it needs permission and a network to build into. |
| **1. Provision** | `terraform apply` creates the bucket, roles, firewalls, load balancer, launch template, group, alarms. | Terraform, S3, IAM, EC2 (security groups), ALB, ASG, CloudWatch | Everything is created in dependency order, identically every time. |
| **2. Boot** | The first server starts, runs the boot script, downloads the code, starts the app. | EC2, S3, IAM | A server becomes useful with no manual steps, and so will every future server. |
| **3. Serve** | The ALB health-checks `/health`; once healthy, candidates reach the site at the ALB address. | ALB, target group, security groups | One stable address; unhealthy servers are never sent traffic. |
| **4. Observe** | Each server counts signed-in users and publishes `ActiveLogins` every minute. | CloudWatch, IAM | This is the signal AWS cannot produce itself. |
| **5. Scale out** | The 13th sign-in pushes the Sum above 12; the alarm fires; the policy sets the group to 2 (or 3) servers; the new server boots (Phase 2), passes health checks and joins the ALB. | CloudWatch alarm, scaling policy, ASG, EC2, S3, ALB | Capacity grows with demand, with no human involved. |
| **6. Scale in** | After users leave (or sessions expire) and the Sum stays below 8 for 5 minutes, the group returns to 1 server. | CloudWatch alarm, scaling policy, ASG | You stop paying for capacity you no longer need. |
| **7. Tear down** | `terraform destroy` removes everything it created. | Terraform | No leftover resources and no surprise bill. |

### Scale-out timeline (typical, not guaranteed)

```
 0:00   the 13th candidate signs in             app.py now holds 13 live sessions
 0:01   the instance reports ActiveLogins = 13   (the badge already shows "Scaling Triggered")
 1:00   alarm evaluates: Sum 13 is above 12      state: ALARM
 1:05   scaling policy runs                      desired capacity 1 → 2
 1:10   Auto Scaling launches instance #2        boots, pulls code from S3, starts the app
 ~4:00  two health checks pass (15 s apart)      the ALB starts sending traffic to #2
 ──────────────────────────────────────────────────────────────────────────────────────
 ~15:00 users leave / sessions expire            Sum below 8 for 5 minutes → back to 1 instance
```

## 💻 Local development

Run from the **repository root** (the app looks for `templates/` relative to where it starts):

```bash
git clone https://github.com/MaxwellMensah/retrograde.git
cd retrograde

python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

CW_PUBLISH=false uvicorn app:app --reload --port 8000
```

Open **http://localhost:8000**. `CW_PUBLISH=false` keeps the login counts local instead of trying to reach
AWS. They are still visible at `/api/traffic-status`.

**Editing the frontend:** the page's Tailwind CSS is compiled into the file (no CDN). If you add Tailwind
classes the page has not used before, rebuild the stylesheet and replace the inlined block:

```bash
echo '@tailwind base;@tailwind components;@tailwind utilities;' > input.css
npx tailwindcss@3.4.17 -i input.css --content templates/index.html --minify -o tailwind.min.css
```

**Simulating traffic locally or on AWS:**

```bash
python simulate_logins.py --url http://localhost:8000 --users 13
```

---

## ⚙️ Configuration reference

Environment variables read by `app.py` (all optional; Terraform sets the ones that matter on AWS):

| Variable | Default | Meaning |
|---|---|---|
| `SCALE_THRESHOLD` | `12` | Scaling is "triggered" above this many signed-in users |
| `SESSION_TTL_SECONDS` | `600` | A login with no heartbeat for this long stops counting |
| `ASG_NAME` | *(empty)* | Auto Scaling Group name: metric dimension and fleet-size lookup |
| `CW_PUBLISH` | `true` | Set `false` locally to skip CloudWatch |
| `CW_NAMESPACE` | `Retrograde/Portal` | CloudWatch namespace |
| `AWS_REGION` | *(from the instance)* | Region for the AWS calls |
| `INSTANCE_ID`, `AZ` | *(auto-detected)* | Override the detected instance details (local testing) |

---

## 👥 Presentation demo accounts

You can use the following quick-test credentials on the sign-in page:

* **Candidate 1:** `maxwell` / `maxwell@gmail.com` (profile gender M, shows the Shrek picture)
* **Candidate 2:** `esther` / `esther@gmail.com` (profile gender F, shows the Fiona picture)
* **Candidate 3:** `student1` / `student1@retrograde-demo.com`

`student1` to `student40` all exist (`studentN` / `studentN@retrograde-demo.com`). `simulate_logins.py` uses
them to create load.

---

## 🛟 Troubleshooting

| Symptom | Likely cause and fix |
|---|---|
| `terraform plan` cannot find the VPC | The `Name` tag does not match `vpc_name`. Check it, or pass `-var vpc_name=...`. |
| "needs subnets in at least 2 Availability Zones" | The VPC does not have 2 public subnets in different zones. Pass `-var 'subnet_ids=[...]'`. |
| Role creation denied (IAM) | Your account blocks creating roles. Pass `-var instance_profile_name=<existing profile>`; it needs S3 read and `cloudwatch:PutMetricData`. |
| `apply` waits about 15 minutes, then fails | The first server never became healthy. Open it with Session Manager (EC2 → Connect) and read `/var/log/retrograde-bootstrap.log`, then run `systemctl status retrograde` and `journalctl -u retrograde -n 50`. |
| 502 or 503 right after `apply` | Servers are still booting (allow about 5 minutes) or are failing the health check. Check the target group's health status. |
| Alarm stuck on "Insufficient data" | Metrics are not arriving. Check the instance log for `CloudWatch <- active_logins=`; confirm `boto3` is installed, `CW_PUBLISH` is not `false`, and the role allows `PutMetricData`. |
| Badge shows a lower count than expected after scale-out | Each instance shows its own count; CloudWatch's Sum is the fleet-wide number. |
| Profile picture shows initials instead of Shrek or Fiona | An old page or old `app.py` is being served. Update both, then run the instance refresh above. |
| Changes do not appear after redeploying | Running servers keep old code until replaced. Run the instance refresh command. |

---

## 🔐 Security notes and known limits

* **HTTP only.** The demo is served over plain HTTP on port 80, so browsers show "Not secure". HTTPS needs a
  custom domain and a certificate (AWS Certificate Manager) on the load balancer.
* **Least privilege.** Servers accept traffic only from the load balancer; the S3 bucket is private; the IAM
  role can only read the app bundle, publish to one CloudWatch namespace and read the group size. IMDSv2 is
  required.
* **Demo data lives in memory.** Students and sessions are held in `app.py`, not a database, and demo
  credentials are public. A production version would use a database (for example RDS or DynamoDB) and real
  authentication.
* **Counts are per instance.** Stickiness keeps them accurate; with it disabled a user could be counted
  twice. A shared store (Redis or DynamoDB) would remove this dependency.
* **Timing.** Metrics are reported once a minute, so allow 1-2 minutes between the 13th sign-in and the alarm.
* **Cost.** The load balancer and servers are billed hourly. Destroy the environment when you are done.

The manual, step-by-step version of the AWS setup (the same resources, created with the CLI) is kept in
[`AWS_SETUP.md`](AWS_SETUP.md).

---

## 📄 License

Distributed under the **MIT License**. See `LICENSE` for more information.
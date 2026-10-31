# Auto-scaling on logins: AWS setup

```
browser -> ALB -> EC2 instances running app.py
                       |  once a minute, each instance publishes its login count
                       v
              CloudWatch metric  Retrograde/Portal : ActiveLogins   (Sum = whole fleet)
                       |  alarm: Sum > 12   (the 13th logged-in user)
                       v
              Auto Scaling Group policy -> launches more instances (the ALB then sends them traffic)
```

An ALB only spreads traffic; the thing that adds instances is the **Auto Scaling Group**, and it needs a
CloudWatch alarm to tell it when. `app.py` now publishes that metric. Replace `retrograde-asg` below with
your ASG's real name.

## 1. Let the instances publish metrics (IAM)
Attach this to the **instance profile / role** used by your launch template:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    { "Effect": "Allow", "Action": "cloudwatch:PutMetricData", "Resource": "*",
      "Condition": { "StringEquals": { "cloudwatch:namespace": "Retrograde/Portal" } } },
    { "Effect": "Allow", "Action": "autoscaling:DescribeAutoScalingGroups", "Resource": "*" }
  ]
}
```
(The second line only lets the page show how many instances are running.)

## 2. On every instance
```bash
pip install boto3
```
and give the app its settings, for example in `/etc/retrograde.env` (point the systemd service at it with
`EnvironmentFile=/etc/retrograde.env`), or in the launch template's user data:
```
ASG_NAME=retrograde-asg
SCALE_THRESHOLD=12
```
Put the updated `app.py` and `templates/retro_test.html` (the new page) in your AMI / deployment, and
restart the service. Check the log for `Retrograde backend up on instance i-...`.

## 3. Target group + Auto Scaling Group
- **Health check path:** `/health`
- **Stickiness: turn it on** (target group -> Attributes -> Stickiness -> load balancer generated cookie).
  Each instance counts only the users who are signed in *on it*; stickiness keeps a user's heartbeats and
  sign-out on the same instance so nobody is counted twice.
- **ASG:** health check type `ELB`, minimum 1, desired 1, **maximum 3 or more** (the policy below goes up to 3).

## 4. The scaling policy and alarm (13th user triggers it)
```bash
# scale OUT: 13 to 24 users -> 2 instances, 25+ -> 3 instances
aws autoscaling put-scaling-policy --auto-scaling-group-name retrograde-asg \
  --policy-name retrograde-scale-out --policy-type StepScaling \
  --adjustment-type ExactCapacity --metric-aggregation-type Maximum --estimated-instance-warmup 120 \
  --step-adjustments MetricIntervalLowerBound=0,MetricIntervalUpperBound=12,ScalingAdjustment=2 MetricIntervalLowerBound=12,ScalingAdjustment=3
# -> copy the PolicyARN it prints

aws cloudwatch put-metric-alarm --alarm-name retrograde-logins-high \
  --namespace Retrograde/Portal --metric-name ActiveLogins \
  --dimensions Name=AutoScalingGroupName,Value=retrograde-asg \
  --statistic Sum --period 60 --evaluation-periods 1 \
  --threshold 12 --comparison-operator GreaterThanThreshold --treat-missing-data notBreaching \
  --alarm-actions <SCALE_OUT_POLICY_ARN>
```
Optional, to scale back in once people leave (below 8 users for 5 minutes -> 1 instance):
```bash
aws autoscaling put-scaling-policy --auto-scaling-group-name retrograde-asg \
  --policy-name retrograde-scale-in --policy-type StepScaling \
  --adjustment-type ExactCapacity --metric-aggregation-type Maximum \
  --step-adjustments MetricIntervalUpperBound=0,ScalingAdjustment=1

aws cloudwatch put-metric-alarm --alarm-name retrograde-logins-low \
  --namespace Retrograde/Portal --metric-name ActiveLogins \
  --dimensions Name=AutoScalingGroupName,Value=retrograde-asg \
  --statistic Sum --period 60 --evaluation-periods 5 \
  --threshold 8 --comparison-operator LessThanThreshold --treat-missing-data notBreaching \
  --alarm-actions <SCALE_IN_POLICY_ARN>
```
Already made an alarm at 12? Point it at exactly this: namespace `Retrograde/Portal`, metric `ActiveLogins`,
dimension `AutoScalingGroupName`, statistic **Sum**, period 60 s, greater than 12.

## 5. Test it
```bash
python simulate_logins.py --url http://<your-ALB-DNS-name> --users 12 --logout   # just under: nothing happens
python simulate_logins.py --url http://<your-ALB-DNS-name> --users 13            # the 13th crosses it
```
Then watch, in order: the page badge changes to "Scaling Triggered" immediately; about 1-2 minutes later
CloudWatch -> Alarms shows `retrograde-logins-high` in **ALARM**; EC2 -> Auto Scaling groups -> **Activity**
shows an instance launching; a few minutes after that the page shows "Scaled Up (ASG Active - 2 Instances)".

## Good to know
- **Timing:** each instance publishes once a minute, so allow about 1-2 minutes between the 13th login and the alarm.
- **What counts as a login:** distinct students with a live session. The same student signing in twice counts
  once. A session ends on sign-out, when the tab closes, or after 10 minutes without a heartbeat
  (`SESSION_TTL_SECONDS`). Users from the simulate script never send heartbeats, so they drop out after 10 minutes.
- **After scale-out** each instance's page badge shows *its own* count. CloudWatch (Sum) is the fleet-wide truth.
- **Not tested on real AWS:** I could not reach AWS from where I built this. The Python (counts, 12-vs-13
  boundary, sessions, metric payloads) was tested locally with a stand-in AWS client; the CLI commands above
  follow the AWS documentation but run them once and confirm the alarm shows data in CloudWatch.

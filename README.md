# Enterprise CI/CD Platform — Expense Tracker Backend

GitOps pipeline: GitHub Actions (build/test/scan/push) → Terraform (infra) →
EKS + ArgoCD (deploy) → Kubernetes Job (auto DB migration) → Prometheus/Grafana + CloudWatch (observe).

## Folder structure
```
cicd-platform/
├── app/                        # expense-tracker-backend source code
├── docker/                     # Dockerfile, .dockerignore
├── .github/workflows/ci.yml    # build, test, scan, push to ECR, bump GitOps tag
├── jenkins/Jenkinsfile         # optional Terraform+Ansible+ArgoCD orchestration
├── terraform/
│   ├── modules/{vpc,ecr,eks,alb,rds}/  # reusable infra modules (RDS = auto database)
│   └── envs/prod/                       # wires modules together, S3 backend, EC2
├── ansible/                    # optional node bootstrap (skipped automatically on Windows)
├── k8s/
│   ├── base/                   # Deployment, Service, HPA, Ingress, Secret example,
│   │                           # migration-job.yaml (auto-runs DB migrations)
│   └── overlays/{dev,prod}/    # kustomize per-env image + replica patches
├── argocd/application.yaml     # GitOps Application pointing at k8s/overlays/prod
├── monitoring/                 # Prometheus + Grafana configs
└── scripts/
    ├── config.env              # only KEY_PAIR_NAME etc — nothing else to fill in
    ├── bootstrap-all.sh        # ONE script that does everything, Git Bash compatible
    └── deploy.sh                # manual single-deploy helper (used internally too)
```

## Alternative: run everything on the server instead of your laptop

If you don't want to install Docker Desktop / kustomize on Windows at all, use this path
instead — the EC2 server Terraform creates installs its own tools automatically.

On your laptop (only needs `terraform` and `aws` CLI, which you already have):
```
chmod +x scripts/bootstrap-infra-only.sh
./scripts/bootstrap-infra-only.sh
```
This builds all AWS infra and prints your server's IP plus exact `scp`/`ssh` commands.
Wait 2-3 minutes after it finishes for the server to install Docker/kubectl/kustomize/
Ansible/ArgoCD CLI on itself, then copy the project up and SSH in as instructed, and run:
```
cd ~/cicd-platform
chmod +x scripts/remote-deploy.sh
./scripts/remote-deploy.sh
```
This does everything else — Ansible, kubectl, ArgoCD, secrets, build/push/deploy, and the
automatic DB migration — running entirely on the server. No local Docker install needed.

## Step-by-step execution (Git Bash on Windows, all on your laptop)

### Step 1 — Get your AWS access keys
Log into the AWS Console in your browser at console.aws.amazon.com. Go to **IAM → Users →
your username → Security credentials tab → Create access key**. Choose "Command Line
Interface (CLI)" as the use case if asked. Copy both the **Access Key ID** and the
**Secret Access Key** it shows you — the secret is only shown once, so save both somewhere
safe like a notes file.

### Step 2 — Unzip the project
Right-click `enterprise-cicd-platform.zip` in your Downloads folder → Extract All → choose
a simple destination path with no unusual characters, e.g. `E:\cicd-platform`.

### Step 3 — Open the project in VS Code with Git Bash
Open VS Code → File → Open Folder → select the extracted `cicd-platform` folder. Open a
terminal with `` Ctrl + ` ``. If it doesn't already say "bash" or "MINGW64" at the top of
the terminal panel, click the dropdown arrow next to the `+` in the terminal panel and
choose "Git Bash."

### Step 4 — Install required tools (if not already installed)
Check what you already have by running each of these in the Git Bash terminal:
```
docker --version
aws --version
terraform --version
kubectl version --client
kustomize version
```
For anything missing, open a separate **Windows PowerShell as Administrator** (Start menu
→ type PowerShell → right-click → Run as administrator) and run the matching command:
```
winget install -e --id Docker.DockerDesktop
winget install -e --id Amazon.AWSCLI
winget install -e --id Hashicorp.Terraform
winget install -e --id Kubernetes.kubectl
```
For kustomize, download the latest release for Windows from
https://github.com/kubernetes-sigs/kustomize/releases and put `kustomize.exe` somewhere on
your PATH (e.g. `C:\Windows`). After installing anything, close and reopen Git Bash so it
picks up the new tools. If you installed Docker Desktop, open it once and leave it running
in the background any time you work on this project.

### Step 5 — Connect the AWS CLI to your account
In Git Bash:
```
aws configure
```
Paste your Access Key ID, paste your Secret Access Key, type `us-east-1` for region, press
Enter for the last question (output format). Confirm it worked:
```
aws sts get-caller-identity
```
This should print your AWS account number, not an error.

### Step 6 — Make sure your app code is inside the `app/` folder
Open the file explorer in VS Code and check `app/package.json` exists. If it's missing,
pull it in:
```
cd "path/to/cicd-platform"
git clone https://github.com/Andacanaver/expense-tracker-backend.git /tmp/app-source
cp -r /tmp/app-source/* ./app/
rm -rf /tmp/app-source
```

### Step 7 — Make the bootstrap script runnable
```
cd "path/to/cicd-platform"
chmod +x scripts/bootstrap-all.sh scripts/deploy.sh
```

### Step 8 — Run the one automated script
```
./scripts/bootstrap-all.sh
```
This single command does everything from here: creates your EC2 key pair, creates a
Terraform state bucket, builds all AWS infrastructure (VPC, EKS cluster, ECR registry, load
balancer, EC2 server, and an RDS Postgres database), connects kubectl to the new cluster,
installs ArgoCD, generates your JWT secret automatically, builds your database connection
string automatically from the new RDS database, creates your Kubernetes secrets, builds and
pushes your Docker image, and deploys the app. **It also creates the database tables
automatically** — no separate migration step needed, since a Kubernetes Job runs your
`npm run migrate` command inside the cluster on every deploy, before the app starts.
This takes roughly 20–30 minutes, mostly waiting on AWS to create the EKS cluster and RDS
database. Don't close the terminal while it runs.

### Step 9 — Save the final output block
When it finishes, it prints something like:
```
ArgoCD admin password  : ...
Load balancer address  : http://...elb.amazonaws.com/
EC2 server public IP   : ...
Database endpoint      : ...
JWT secret used         : ...
```
Copy this entire block into a notes file — these values (especially the ArgoCD password
and JWT secret) are not shown again automatically.

### Step 10 — Verify everything is actually running
In the same Git Bash terminal:
```
kubectl -n expense-tracker-prod get pods,svc,ingress,hpa
```
You should see your app pod with `STATUS: Running`. Check that the migration ran
successfully:
```
kubectl -n expense-tracker-prod logs job/expense-tracker-db-migrate
```
This should show Postgrator applying your `001` and `002` migration files. Then test the
app itself using the load balancer address from Step 9:
```
curl http://<load-balancer-address>/
```
A response back (not a timeout) means your app is live and reachable.

### Step 11 — Connect GitHub Actions for automatic future deployments
Go to your repo on github.com → **Settings → Secrets and variables → Actions → New
repository secret**. Add:
- `AWS_ROLE_ARN` — requires a one-time IAM role setup trusting GitHub's OIDC provider (ask
  for a walkthrough if you want this configured).
- `SLACK_WEBHOOK_URL` — optional, only needed for Slack build notifications.

Once this is set, every future `git push` to `main` automatically tests, builds, scans,
pushes, and deploys your app — including re-running the migration Job if you add new
migration files — with no manual steps required.

## Notes
- The RDS database sits in a private subnet for security; your laptop cannot connect to it
  directly, which is why migrations run as a Job *inside* the cluster instead.
- Ansible (server configuration) is skipped automatically when running from Git Bash, since
  it requires a Linux shell. This is not required for the app to work — your app runs on
  managed EKS nodes, not plain EC2 servers. The EC2 server created by Terraform is optional
  (e.g. for future SSH-based debugging) and does not affect the app's operation.
- Re-running `./scripts/bootstrap-all.sh` is safe — it skips anything already created (key
  pair, state bucket) and re-applies the rest.
# trigger

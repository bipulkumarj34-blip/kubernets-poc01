# K8s Externalized Configuration PoC

## Project Overview

**Objective:** Deploy an Nginx application to GKE where configuration (Environment Variables) and Secrets (DB Password) are managed outside the container and injected at runtime. 

**Key Feature:** Automatic Rollout Restart—when you update the ConfigMap in Terraform, Kubernetes automatically restarts the pods to apply changes.

---

## Step 1: Initial Local Requirements

Ensure these are installed on your Mac:

1. **Google Cloud SDK:** `gcloud --version`
2. **Terraform:** `terraform -version`
3. **kubectl:** `kubectl version --client`
4. **Rancher Desktop:** Open the app to ensure the K8s engine is running


---

## Step 2: One-Time GCP "Memory" Setup (The Bucket)

Terraform needs a "Backend" to remember what it has built. Without this, you get 409 Already Exists errors. Run this in your terminal:

```bash
# 1. Login
gcloud auth login
gcloud config set project devops-489010

# 2. Create the State Bucket
gcloud storage buckets create gs://devops-489010-tfstate --location=us-central1

# 3. Enable the GKE API
gcloud services enable container.googleapis.com
```

---

## Step 3: Setup GitHub "Trust" (Keyless Auth)

Run these commands once to allow GitHub to talk to GCP without using a risky JSON key.

```bash
# 1. Create Identity Pool
gcloud iam workload-identity-pools create "github-pool" --location="global"

# 2. Create OIDC Provider
gcloud iam workload-identity-pools providers create-oidc "github-provider" \
  --location="global" --workload-identity-pool="github-pool" \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository"

# 3. Link your existing Service Account (Replace [SA_EMAIL] and [REPO])
gcloud iam service-accounts add-iam-policy-binding "[SA_EMAIL]" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/$(gcloud projects describe devops-489010 --format='value(projectNumber)')/locations/global/workloadIdentityPools/github-pool/attribute.repository/[YOUR_USERNAME]/[YOUR_REPO]"
```

---

## Step 4: The Terraform Configuration (main.tf)

Create this file in your repository root.

```hcl
terraform {
  backend "gcs" {
    bucket = "devops-489010-tfstate"
    prefix = "terraform/state"
  }
}

provider "google" {
  project = "devops-489010"
  region  = "us-central1"
}

resource "google_container_cluster" "primary" {
  name               = "poc-cluster"
  location           = "us-central1-a"
  initial_node_count = 1
  workload_identity_config { workload_pool = "devops-489010.svc.id.goog" }
}

provider "kubernetes" {
  host                   = "https://${google_container_cluster.primary.endpoint}"
  cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "gke-gcloud-auth-plugin"
  }
}

resource "kubernetes_config_map_v1" "app_config" {
  metadata { name = "app-config" }
  data     = { "APP_COLOR" = "blue" }
}

resource "kubernetes_secret_v1" "db_pass" {
  metadata { name = "db-pass" }
  data     = { "password" = "poc-password-123" }
}

resource "kubernetes_deployment_v1" "app" {
  metadata { name = "config-poc" }
  spec {
    replicas = 1
    selector { match_labels = { app = "poc" } }
    template {
      metadata {
        labels = { app = "poc" }
        annotations = { "checksum/config" = sha256(jsonencode(kubernetes_config_map_v1.app_config.data)) }
      }
      spec {
        container {
          name  = "webapp"
          image = "nginx:latest"
          env_from { config_map_ref { name = "app-config" } }
          env {
            name = "DB_PASSWORD"
            value_from { secret_key_ref { name = "db-pass", key = "password" } }
          }
        }
      }
    }
  }
}
```

---

## Step 5: The GitHub Workflow (.github/workflows/deploy.yml)

This automates the deployment every time you push code.

```yaml
name: "GCP Deploy"
on: [push]
permissions: { id-token: write, contents: read }
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: 'projects/[PROJECT_NUMBER]/locations/global/workloadIdentityPools/github-pool/providers/github-provider'
          service_account: '[SA_EMAIL]'
      - uses: google-github-actions/setup-gcloud@v2
        with: { install_components: 'gke-gcloud-auth-plugin' }
      - uses: hashicorp/setup-terraform@v3
      - run: terraform init && terraform apply -auto-approve
```

---

## Step 6: How to Run & Verify

1. **Push Code:** `git add . && git commit -m "poc setup" && git push origin main`
2. **Connect Locally:** Once the GitHub Action is green, run: 
   ```bash
   gcloud container clusters get-credentials poc-cluster --zone us-central1-a
   ```
3. **View in Rancher Desktop:**
   - Change Context to `gke_devops-489010_us-central1-a_poc-cluster`
   - View the Pod in the default namespace
   - Check "Environment Variables" to see APP_COLOR and DB_PASSWORD
4. **Test Rollout:** Change APP_COLOR to "red" in main.tf, push, and watch the pod restart in Rancher.

---

## Step 7: Graceful Shutdown (Delete everything)

To stop GCP charges:

1. **Run locally:** `terraform destroy -auto-approve`
2. **Clean Kubeconfig:** `kubectl config delete-context gke_devops-489010_us-central1-a_poc-cluster`


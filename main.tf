provider "google" {
  project = "devops-489010"
  region  = "us-central1"
}

# 1. Create GKE Cluster with Workload Identity enabled
resource "google_container_cluster" "primary" {
  name     = "poc-cluster"
  location = "us-central1-a"
  initial_node_count = 1
  
  workload_identity_config {
    workload_pool = "devops-489010.svc.id.goog"
  }
}

# 2. K8s Provider (Connects to the cluster we just built)
provider "kubernetes" {
  host  = "https://${google_container_cluster.primary.endpoint}"
  cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "gcloud"
    args        = ["container", "clusters", "get-credentials", "poc-cluster", "--zone", "us-central1-a", "--print-access-token"]
  }
}

# 3. ConfigMap & Secret
resource "kubernetes_config_map" "app_config" {
  metadata { name = "app-config" }
  data = { "APP_COLOR" = "blue" }
}

resource "kubernetes_secret" "db_pass" {
  metadata { name = "db-pass" }
  data = { "password" = "poc-password-123" }
}

# 4. Deployment with Injection & Rollout Trigger
resource "kubernetes_deployment" "app" {
  metadata { name = "config-poc" }
  spec {
    replicas = 1
    selector { match_labels = { app = "poc" } }
    template {
      metadata {
        labels = { app = "poc" }
        annotations = {
          # This forces a rollout if the ConfigMap changes
          "checksum/config" = sha256(jsonencode(kubernetes_config_map.app_config.data))
        }
      }
      spec {
        container {
          name  = "webapp"
          image = "nginx"
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
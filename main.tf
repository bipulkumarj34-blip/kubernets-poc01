provider "google" {
  project = "devops-489010"
  region  = "us-central1"
}

resource "google_container_cluster" "primary" {
  name     = "poc-cluster"
  location = "us-central1-a"
  initial_node_count = 1
  
  workload_identity_config {
    workload_pool = "devops-489010.svc.id.goog"
  }
}

# --- Kubernetes Resources ---
resource "kubernetes_config_map" "app_config" {
  metadata { name = "app-config" }
  data = { "APP_COLOR" = "blue" } # Change this to test rollout
}

resource "kubernetes_secret" "db_pass" {
  metadata { name = "db-pass" }
  data = { "password" = "poc-password-123" }
}

resource "kubernetes_deployment" "app" {
  metadata { name = "config-poc" }
  spec {
    replicas = 1
    selector { match_labels = { app = "poc" } }
    template {
      metadata {
        labels = { app = "poc" }
        annotations = {
          # This hash forces a restart if you change the ConfigMap
          "checksum/config" = sha256(jsonencode(kubernetes_config_map.app_config.data))
        }
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
provider "google" {
  project = "devops-489010"
  region  = "us-central1"
}

# 1. GKE Cluster Definition
resource "google_container_cluster" "primary" {
  name               = "poc-cluster"
  location           = "us-central1-a"
  initial_node_count = 1
  
  workload_identity_config {
    workload_pool = "devops-489010.svc.id.goog"
  }
}

# 2. Kubernetes Provider Configuration
# This tells Terraform how to connect to the GKE cluster created above
provider "kubernetes" {
  host                   = "https://${google_container_cluster.primary.endpoint}"
  cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "gke-gcloud-auth-plugin" # Uses the plugin we installed
  }
}

# 3. ConfigMap
resource "kubernetes_config_map" "app_config" {
  metadata {
    name = "app-config"
  }
  data = {
    "APP_COLOR" = "blue" 
  }
}

# 4. Secret
resource "kubernetes_secret" "db_pass" {
  metadata {
    name = "db-pass"
  }
  data = {
    "password" = "poc-password-123"
  }
}

# 5. Deployment (Fixed Syntax)
resource "kubernetes_deployment" "app" {
  metadata {
    name = "config-poc"
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "poc"
      }
    }
    template {
      metadata {
        labels = {
          app = "poc"
        }
        annotations = {
          # This forces a rollout if you change the ConfigMap data
          "checksum/config" = sha256(jsonencode(kubernetes_config_map.app_config.data))
        }
      }
      spec {
        container {
          name  = "webapp"
          image = "nginx:latest"

          # Fixed: Multi-line block for ConfigMap Injection
          env_from {
            config_map_ref {
              name = kubernetes_config_map.app_config.metadata[0].name
            }
          }

          # Fixed: Multi-line block for Secret Injection
          env {
            name = "DB_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.db_pass.metadata[0].name
                key  = "password"
              }
            }
          }
        }
      }
    }
  }
}
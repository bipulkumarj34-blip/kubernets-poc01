provider "google" {
  project = "devops-489010"
  region  = "us-central1"
}

resource "google_container_cluster" "primary" {
  name               = "poc-cluster"
  location           = "us-central1-a"
  initial_node_count = 1
  workload_identity_config {
    workload_pool = "devops-489010.svc.id.goog"
  }
}

provider "kubernetes" {
  host                   = "https://${google_container_cluster.primary.endpoint}"
  cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "gke-gcloud-auth-plugin"
  }
}

# Updated to _v1 to remove warnings
resource "kubernetes_config_map_v1" "app_config" {
  metadata {
    name = "app-config"
  }
  data = {
    "APP_COLOR" = "blue"
  }
}

# Updated to _v1
resource "kubernetes_secret_v1" "db_pass" {
  metadata {
    name = "db-pass"
  }
  data = {
    "password" = "poc-password-123"
  }
}

# Updated to _v1
resource "kubernetes_deployment_v1" "app" {
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
          "checksum/config" = sha256(jsonencode(kubernetes_config_map_v1.app_config.data))
        }
      }
      spec {
        container {
          name  = "webapp"
          image = "nginx:latest"
          env_from {
            config_map_ref {
              name = kubernetes_config_map_v1.app_config.metadata[0].name
            }
          }
          env {
            name = "DB_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.db_pass.metadata[0].name
                key  = "password"
              }
            }
          }
        }
      }
    }
  }
}
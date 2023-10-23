# TODO: Update
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "5.0.0"
    }

    google-beta = {
      source  = "hashicorp/google-beta"
      version = "5.0.0"
    }
  }
}

# This was copied from a fuller project - not all these APIs may be required
variable "gcp_apis" {
  description = "List of GCP APIs to enable"
  type        = list(string)
  default = [
    "serviceusage.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "run.googleapis.com",
    "compute.googleapis.com",
    "iam.googleapis.com",
    "storage-api.googleapis.com",
    "storage-component.googleapis.com",
    "storage.googleapis.com",
    "bigquery.googleapis.com",
    "iap.googleapis.com",
    "dataform.googleapis.com",
    "secretmanager.googleapis.com",
    "sqladmin.googleapis.com",
    "bigquerydatatransfer.googleapis.com"
  ]
}

# ============================= #
# Setup                         #
# Create a service account for Cloud Run to use
# ============================= #
resource "google_service_account" "metabase_cloud_run_sa" {
  account_id   = "metabase-cloud-run-sa"
  display_name = "Metabase Cloud Run Service Account"

  depends_on = [google_project_service.enable_apis]
}


# ============================= #
# Artifact Registry Repository  #
# Create the artifact registry repository to store the Metabase Docker image
# ============================= #

resource "google_artifact_registry_repository" "metabase" {
  location      = var.project_region
  repository_id = "metabase"
  description   = "Metabase Docker image"
  format        = "DOCKER"
}

# ============================= #
# Metabase Cloud SQL Database   #
# Create the Cloud SQL database and user for Metabase
# If you would prefer to use an existing database, you can remove this resource and update the environment variables in the Cloud Run deployment
# ============================= #
resource "google_sql_database" "metabase" {
  name     = "metabase"
  instance = google_sql_database_instance.metabase_db.name
}

resource "random_password" "metabase_cloud_sql_user_pw" {
  length           = 16
  special          = true
  override_special = "_%@"
}

resource "google_sql_user" "metabase" {
  name     = "metabase"
  instance = google_sql_database_instance.metabase_db.name
  password = random_password.metabase_cloud_sql_user_pw.result
}

# Grant Cloud Run service account access to Cloud SQL
resource "google_project_iam_member" "metabase_cloud_run_sa" {
  project = var.project_id
  role    = "roles/cloudsql.client"

  member = "serviceAccount:${google_service_account.metabase_cloud_run_sa.email}"
}

resource "google_secret_manager_secret" "metabase_db_password" {
  secret_id = "metabase-db-password"

  labels = {
    # My label
  }

  replication {
    auto {

    }
  }
}

resource "google_secret_manager_secret_iam_member" "metabase_sa" {
  secret_id = google_secret_manager_secret.metabase_db_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.metabase_cloud_run_sa.email}"
}


resource "google_secret_manager_secret_version" "metabase_db_password" {
  secret = google_secret_manager_secret.metabase_db_password.id

  secret_data = random_password.metabase_cloud_sql_user_pw.result
}

# ============================= #
# Metabase Cloud Run Deployment #
# ============================= #

resource "google_cloud_run_service" "metabase" {
  name    = "metabase"
  project = var.project_id
  # Not all regions support custom domains at this time, hence the use of us-central1
  # https://cloud.google.com/run/docs/mapping-custom-domains
  location                   = "us-central1"
  autogenerate_revision_name = true

  template {
    spec {
      containers {
        image = "${google_artifact_registry_repository.metabase.location}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.metabase.name}/metabase:latest"
        ports {
          container_port = 3000
        }

        resources {
          limits = {
            cpu    = "2"   # Tweak this to your needs
            memory = "2Gi" # Tweak this to your needs
          }
        }

        liveness_probe {
          initial_delay_seconds = 3000
          period_seconds        = 30
          timeout_seconds       = 5
          failure_threshold     = 3
          http_get {
            path = "/api/health"
            port = 3000
          }
        }

        env {
          name  = "MB_DB_TYPE"
          value = "postgres"
        }

        env {
          name  = "MB_DB_DBNAME"
          value = google_sql_database.metabase.name
        }

        env {
          name  = "MB_DB_PORT"
          value = "5432"
        }

        env {
          name  = "MB_DB_USER"
          value = google_sql_user.metabase.name
        }

        env {
          name  = "MB_DB_PASS"
          value = random_password.metabase_cloud_sql_user_pw.result
        }

        env {
          name  = "MB_DB_HOST"
          value = "127.0.0.1"
        }

        env {
          name  = "JAVA_OPTS"
          value = "-Xmx1000m"
        }
      }
      container_concurrency = 20

      service_account_name = google_service_account.metabase_cloud_run_sa.email
    }

    metadata {
      labels = {
        "environment" = "production"
      }

      annotations = {
        "autoscaling.knative.dev/minScale"      = "1"
        "autoscaling.knative.dev/maxScale"      = "5"
        "run.googleapis.com/startup-cpu-boost"  = "true"
        "run.googleapis.com/cloudsql-instances" = google_sql_database_instance.metabase_db.connection_name
        "run.googleapis.com/client-name"        = "terraform"
        "run.googleapis.com/sessionAffinity"    = "true"
      }
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }

  lifecycle {
    ignore_changes = [
      metadata[0].annotations["client.knative.dev/user-image"],
      metadata[0].annotations["run.googleapis.com/client-name"],
      metadata[0].annotations["run.googleapis.com/client-version"],
      metadata[0].annotations["run.googleapis.com/operation-id"],
      template[0].metadata[0].annotations["client.knative.dev/user-image"],
      template[0].metadata[0].annotations["run.googleapis.com/client-name"],
      template[0].metadata[0].annotations["run.googleapis.com/client-version"],
    ]
  }
}


# WARNING: While Metabase has authentication, this grants public access to the service. Depending on your preferred authentication method, you may want to remove this or put a different authentication method in front of this e.g. Cloud IAP or Cloudflare Access
resource "google_cloud_run_service_iam_binding" "metabase" {
  location = google_cloud_run_service.metabase.location
  project  = google_cloud_run_service.metabase.project
  service  = google_cloud_run_service.metabase.name
  role     = "roles/run.invoker"

  members = [
    "allUsers",
  ]
}


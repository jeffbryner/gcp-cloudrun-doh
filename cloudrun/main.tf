# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

terraform {
  required_version = ">=0.14"
  required_providers {
    google      = "~> 3.0"
    google-beta = "~> 3.0"
  }

}

# inert terraform stub
resource "random_id" "suffix" {
  byte_length = 2
}


data "google_project" "cloudrun" {
  project_id = var.project_id
}

locals {

  project_name      = data.google_project.cloudrun.name
  project_id        = data.google_project.cloudrun.project_id
  state_bucket_name = format("bkt-%s-%s", "tfstate", local.project_id)
  art_bucket_name   = format("bkt-%s-%s", "artifacts", local.project_id)
  repo_name         = format("cicd-%s", local.project_name)
  gar_repo_name     = format("%s-%s", "prj", "containers")
}

/**
cloud build container
**/

resource "null_resource" "cloudbuild_cloudrun_container" {
  triggers = {
    file_changed = filesha512("./container/Dockerfile")
  }

  provisioner "local-exec" {
    command = <<EOT
      gcloud builds submit ./container/ --project ${local.project_id} --config=./container/cloudbuild.yaml
  EOT
  }
}


# set a project policy to allow allUsers invoke
resource "google_project_organization_policy" "services_policy" {
  project    = local.project_id
  constraint = "iam.allowedPolicyMemberDomains"

  list_policy {
    allow {
      all = true
    }
  }
}

resource "google_cloud_run_service" "default" {
  name     = "cloudrun-srv"
  location = "us-central1"
  project  = local.project_id

  template {
    spec {
      containers {
        image = "us-central1-docker.pkg.dev/${local.project_id}/prj-containers/cloudrun"
        env {
          name  = "NA"
          value = "NA"
        }
        ports {
          container_port = 3000
        }
      }
    }
  }

}

data "google_iam_policy" "noauth" {
  binding {
    role = "roles/run.invoker"
    members = [
      "allUsers",
    ]
  }
}


resource "google_cloud_run_service_iam_policy" "noauth" {
  location = google_cloud_run_service.default.location
  project  = local.project_id
  service  = google_cloud_run_service.default.name

  policy_data = data.google_iam_policy.noauth.policy_data
}

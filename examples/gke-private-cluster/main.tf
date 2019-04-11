# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY A GKE PRIVATE CLUSTER IN GOOGLE CLOUD
# This is an example of how to use the gke-cluster module to deploy a public Kubernetes cluster in GCP
# ---------------------------------------------------------------------------------------------------------------------

# Use Terraform 0.10.x so that we can take advantage of Terraform GCP functionality as a separate provider via
# https://github.com/terraform-providers/terraform-provider-google
terraform {
  required_version = ">= 0.10.3"
}

# ---------------------------------------------------------------------------------------------------------------------
# PREPARE PROVIDERS
# ---------------------------------------------------------------------------------------------------------------------

provider "google" {
  version = "~> 2.3.0"
  project = "${var.project}"
  region  = "${var.region}"
}

provider "google-beta" {
  version = "~> 2.3.0"
  project = "${var.project}"
  region  = "${var.region}"
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY A PRIVATE CLUSTER IN GOOGLE CLOUD
# ---------------------------------------------------------------------------------------------------------------------

module "gke_cluster" {
  # When using these modules in your own templates, you will need to use a Git URL with a ref attribute that pins you
  # to a specific version of the modules, such as the following example:
  # source = "git::git@github.com:gruntwork-io/terraform-google-gke.git//modules/gke-cluster?ref=v0.0.4"
  source = "../../modules/gke-cluster"

  name = "${var.cluster_name}"

  project    = "${var.project}"
  location   = "${var.location}"
  network    = "${module.vpc_network.network}"
  subnetwork = "${module.vpc_network.public_subnetwork}"

  # When creating a private cluster, the 'master_ipv4_cidr_block' has to be defined and the size must be /28
  master_ipv4_cidr_block = "${var.master_ipv4_cidr_block}"

  # This setting will make the cluster private
  enable_private_nodes = "true"

  # To make testing easier, we keep the public endpoint available. In production, we highly recommend restricting access to only within the network boundary, requiring your users to use a bastion host or VPN.
  disable_public_endpoint = "false"

  # With a private cluster, it is highly recommended to restrict access to the cluster master
  # However, for testing purposes we will allow all inbound traffic.
  master_authorized_networks_config = [{
    cidr_blocks = [{
      cidr_block   = "0.0.0.0/0"
      display_name = "all-for-testing"
    }]
  }]

  cluster_secondary_range_name = "${module.vpc_network.public_subnetwork_secondary_range_name}"
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE A NODE POOL
# ---------------------------------------------------------------------------------------------------------------------

resource "google_container_node_pool" "node_pool" {
  provider = "google-beta"

  name     = "private-pool"
  project  = "${var.project}"
  location = "${var.location}"
  cluster  = "${module.gke_cluster.name}"

  initial_node_count = "1"

  autoscaling {
    min_node_count = "1"
    max_node_count = "5"
  }

  management {
    auto_repair  = "true"
    auto_upgrade = "true"
  }

  node_config {
    image_type   = "COS"
    machine_type = "n1-standard-1"

    labels = {
      private-pools-example = "true"
    }

    # Add a private tag to the instances. See the network access tier table for full details:
    # https://github.com/gruntwork-io/terraform-google-network/tree/master/modules/vpc-network#access-tier
    tags = [
      "${module.vpc_network.private}",
      "private-pool-example",
    ]

    disk_size_gb = "30"
    disk_type    = "pd-standard"
    preemptible  = false

    service_account = "${module.gke_service_account.email}"

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]
  }

  lifecycle {
    ignore_changes = ["initial_node_count"]
  }

  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE A CUSTOM SERVICE ACCOUNT TO USE WITH THE GKE CLUSTER
# ---------------------------------------------------------------------------------------------------------------------

module "gke_service_account" {
  # When using these modules in your own templates, you will need to use a Git URL with a ref attribute that pins you
  # to a specific version of the modules, such as the following example:
  # source = "git::git@github.com:gruntwork-io/terraform-google-gke.git//modules/gke-service-account?ref=v0.0.4"
  source = "../../modules/gke-service-account"

  name        = "${var.cluster_service_account_name}"
  project     = "${var.project}"
  description = "${var.cluster_service_account_description}"
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE A NETWORK TO DEPLOY THE CLUSTER TO
# ---------------------------------------------------------------------------------------------------------------------

module "vpc_network" {
  source = "git::git@github.com:gruntwork-io/terraform-google-network.git//modules/vpc-network?ref=v0.0.2"

  name    = "${var.cluster_name}-network-${random_string.suffix.result}"
  project = "${var.project}"
  region  = "${var.region}"

  cidr_block           = "${var.vpc_cidr_block}"
  secondary_cidr_block = "${var.vpc_secondary_cidr_block}"
}

# Use a random suffix to prevent overlap in network names
resource "random_string" "suffix" {
  length  = 4
  special = false
  upper   = false
}

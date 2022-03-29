terraform {
  cloud {
    organization = ""

    workspaces {
      name = ""
    }
  }
}

provider "google" {
  project = ""
  region = ""

}

#Configure Network
resource "google_compute_network" "vpc_network" {
  name = "kubernetes-network"
  routing_mode = "REGIONAL"
  auto_create_subnetworks = "false"
}

#Create London Subnet
resource "google_compute_subnetwork" "london_subnet" {
  name = "k8s-london"
  region      = "europe-west2"
  ip_cidr_range = "172.27.0.0/20"
  network       = google_compute_network.vpc_network.self_link
  private_ip_google_access = true
}

#Firewall Rules
resource "google_compute_firewall" "internal_rules" {
  name        = "k8s-firewall"
  network     = google_compute_network.vpc_network.self_link
  description = "Creates firewall rule  for k8s"

  allow {
    protocol  = "tcp"
    ports     = ["0-65535"]
  }
  allow {
    protocol = "udp"
    ports     = ["0-65535"]
  }
  allow {
    protocol = "icmp"
  }
  source_ranges = ["172.27.0.0/20"]
}

resource "google_compute_firewall" "external-rules" {
  name        = "k8s-firewall-external"
  network     = google_compute_network.vpc_network.self_link
  description = "Creates external firewall rule for k8s"

  allow {
    protocol  = "tcp"
    ports     = ["80", "443", "8080"]
  }
  allow {
    protocol = "udp"
    ports     = ["80", "443", "8080"]
  }
  allow {
    protocol = "icmp"
  }
  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_firewall" "rules" {
  name        = "k8s-firewall-external-ssh"
  network     = google_compute_network.vpc_network.self_link
  description = "Creates external firewall SSH rule for k8s"

  allow {
    protocol  = "tcp"
    ports     = ["22"]
  }
  source_ranges = [""]
}


# GCP Router for NAT Instance
resource "google_compute_router" "router" {
  name    = "kubernetes-router"
  network = google_compute_network.vpc_network.self_link
  region  = google_compute_subnetwork.london_subnet.region
}


#Cloud NAT
resource "google_compute_router_nat" "nat" {
  name                               = "kubernetes-nat"
  router                             = google_compute_router.router.name
  region                             = google_compute_router.router.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}


#Configuration of Kubernetes

resource "google_container_cluster" "primary" {
  name     = "k8s-ca-cluster"
  location = google_compute_subnetwork.london_subnet.region
  remove_default_node_pool = true
  initial_node_count       = 1
  network = google_compute_network.vpc_network.self_link
  subnetwork = google_compute_subnetwork.london_subnet.self_link
  #Enabling StackDriver Kubernetes Monitoring Features
  monitoring_service = "monitoring.googleapis.com/kubernetes"
  logging_service    = "logging.googleapis.com/kubernetes"
  cluster_ipv4_cidr = "172.16.0.0/16"
  network_policy {
    enabled = false
  }
}

#Configuration of K8s Nodes
resource "google_container_node_pool" "primary_nodes" {
  name       = "k8s-node-pool"
  location   = google_compute_subnetwork.london_subnet.region
  cluster    = google_container_cluster.primary.name
  node_count = 1
  node_config {
    machine_type = "e2-medium"
    oauth_scopes    = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
    
  }
  autoscaling {
    max_node_count = 3
    min_node_count = 1
  } 
}

resource "google_project_service" "monitoring" {
  service            = "monitoring.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "container" {
  service            = "container.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "logging" {
  service            = "logging.googleapis.com"
  disable_on_destroy = false
}


#Build out Cloud Build Trigger

resource "google_cloudbuild_trigger" "Backend_trigger" {
  description = "Backend Production branch"
  filename = "cloudbuild.yaml"
   github {
    owner = ""
    name = "backend"
    push {
      branch = "^main"
    }
  }
}

resource "google_cloudbuild_trigger" "Backend_trigger_stagging" {
  description = "Backend Stagging branch"
  filename = "cloudbuild.yaml"
   github {
    owner = ""
    name = "backend"
    push {
      branch = "^dev"
    }
  }
}

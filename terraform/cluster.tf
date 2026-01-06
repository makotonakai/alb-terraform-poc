resource "google_compute_network" "default" {
  name = "example-network"

  auto_create_subnetworks  = false
  enable_ula_internal_ipv6 = true
}

resource "google_compute_subnetwork" "default" {
  name = "example-subnetwork"

  ip_cidr_range = "10.0.0.0/16"
  region        = "asia-northeast1"

  stack_type       = "IPV4_IPV6"
  ipv6_access_type = "INTERNAL" 

  network = google_compute_network.default.id
  secondary_ip_range {
    range_name    = "services-range"
    ip_cidr_range = "192.168.0.0/24"
  }

  secondary_ip_range {
    range_name    = "pod-ranges"
    ip_cidr_range = "192.168.1.0/24"
  }
}

resource "google_compute_subnetwork" "proxy_subnet" {
  name = "proxy-subnetwork"

  ip_cidr_range = "10.1.0.0/23"
  region        = "asia-northeast1"

  network = google_compute_network.default.id
  purpose = "REGIONAL_MANAGED_PROXY"
  role    = "ACTIVE"
}

resource "google_container_cluster" "default" {
  name = "example-autopilot-cluster"

  location                 = "asia-northeast1"
  enable_autopilot         = true
  enable_l4_ilb_subsetting = true

  network    = google_compute_network.default.id
  subnetwork = google_compute_subnetwork.default.id

  ip_allocation_policy {
    stack_type                    = "IPV4_IPV6"
    services_secondary_range_name = google_compute_subnetwork.default.secondary_ip_range[0].range_name
    cluster_secondary_range_name  = google_compute_subnetwork.default.secondary_ip_range[1].range_name
  }

  # Set `deletion_protection` to `true` will ensure that one cannot
  # accidentally delete this instance by use of Terraform.

  deletion_protection = false
}

resource "google_compute_firewall" "lb_fw" {
  name    = "lb-fw"
  network = google_compute_network.default.name

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }

  # The ip range for the health check probes can be found in the following link
  # https://docs.cloud.google.com/load-balancing/docs/health-check-concepts#ip-ranges

  source_ranges = ["10.0.0.0/16", "192.168.0.0/24", "192.168.1.0/24", "35.191.0.0/16", "130.211.0.0/22"]

}

resource "google_compute_firewall" "proxy_fw" {
  name    = "proxy-fw"
  network = google_compute_network.default.name

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }

  source_ranges = ["10.1.0.0/23"]

}

# Put name and zone after it is generated after the service deployment
data "google_compute_network_endpoint_group" "default" {
  name = "k8s1-a70e9872-default-curl-nodeport-8080-98b4c2bc"
  zone = "asia-northeast1-c"
}

resource "google_compute_region_backend_service" "app_backend" {
  name                  = "app-backend"
  protocol              = "HTTP"
  load_balancing_scheme = "INTERNAL_MANAGED"
  timeout_sec           = 30
  port_name = "http"

  backend {
    group                 = data.google_compute_network_endpoint_group.default.id
    balancing_mode        = "RATE"
    capacity_scaler = 1.0
    max_rate_per_endpoint = 100
  }

  health_checks = [google_compute_region_health_check.http.id]
}

resource "google_compute_region_health_check" "http" {
  name = "app-hc"

  http_health_check {
    port = "8080"
    request_path = "/"
  }
}

resource "google_compute_region_url_map" "app" {
  name            = "app-url-map"
  default_service = google_compute_region_backend_service.app_backend.id
}

resource "google_compute_region_target_http_proxy" "app" {
  name    = "app-http-proxy"
  url_map = google_compute_region_url_map.app.id
}

resource "google_compute_forwarding_rule" "app" {
  name                  = "app-forwarding-rule"
  depends_on            = [google_compute_subnetwork.proxy_subnet]
  target                = google_compute_region_target_http_proxy.app.id
  load_balancing_scheme = "INTERNAL_MANAGED"
  network               = google_compute_network.default.id
  subnetwork            = google_compute_subnetwork.default.id
  port_range            = "8080"
}


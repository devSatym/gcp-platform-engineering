platform_config = {
  project_id   = "valiant-house-502004-k2"
  environment  = "dev"
  region       = "us-central1"
  cluster_name = "dev-platform-gke"

  labels = {
    environment      = "dev"
    cost_profile     = "low"
    availability     = "reduced"
    security_profile = "development"
    managed_by       = "terraform"
    platform         = "gcp-devsecops"
  }

  network = {
    vpc_name               = "dev-platform-vpc"
    gke_subnet_cidr        = "10.10.0.0/21"
    management_subnet_cidr = "10.10.8.0/27"
    proxy_subnet_cidr      = "10.10.8.64/26"
    gke_pods_cidr          = "10.110.0.0/18"
    gke_services_cidr      = "10.120.0.0/22"
  }

  router = { name = "dev-platform-router" }
  nat = {
    name             = "dev-platform-nat"
    min_ports_per_vm = 32
  }
  firewall         = { internal_cidr = "10.10.0.0/16" }
  service_accounts = { secret_ids = [] }

  gke = {
    location_type  = "zonal"
    node_locations = ["us-central1-a"]
    node_pools = {
      system = {
        name         = "dev-system"
        machine_type = "e2-medium"
        min_count    = 1
        max_count    = 1
        disk_size_gb = 30
        labels       = { workload = "system" }
        taints       = [{ key = "workload", value = "system", effect = "NO_SCHEDULE" }]
      }
      general = {
        name         = "dev-general"
        machine_type = "e2-standard-2"
        min_count    = 1
        max_count    = 2
        disk_size_gb = 50
        labels       = { workload = "general" }
      }
      spot = {
        name         = "dev-spot"
        machine_type = "e2-standard-2"
        min_count    = 0
        max_count    = 1
        disk_size_gb = 30
        spot         = true
        labels       = { workload = "spot" }
        taints       = [{ key = "workload", value = "spot", effect = "NO_SCHEDULE" }]
      }
    }
    autoscaling = { enabled = true, profile = "BALANCED" }
    private_cluster = {
      enabled                 = true
      enable_private_endpoint = false
      master_authorized_cidrs = []
    }
    release_channel                 = "REGULAR"
    enable_gateway_api              = false
    enable_cloud_dns                = false
    enable_gcs_fuse_csi             = false
    enable_vertical_pod_autoscaling = false
    enable_managed_prometheus       = false
    binary_authorization_mode       = "DISABLED"
    deletion_protection             = false
  }

  artifact_registry = { repository_id = "dev-images" }
  github            = { repository = "devSatym/gcp-platform-engineering" }
  argocd = {
    # Argo CD v3 supports the Kubernetes 1.35 API schema used by this GKE
    # cluster. Apply this Terraform upgrade through the normal reviewed flow.
    chart_version = "10.3.3"
    git_repo_url  = "https://github.com/devSatym/gcp-platform-engineering.git"
  }
}

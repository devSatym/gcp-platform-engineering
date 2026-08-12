platform_config = {
  project_id   = "replace-with-staging-project-id"
  environment  = "staging"
  region       = "replace-with-staging-region"
  cluster_name = "replace-with-staging-cluster-name"

  labels = {
    environment      = "staging"
    cost_profile     = "medium"
    availability     = "production-like"
    security_profile = "staging"
    managed_by       = "terraform"
    platform         = "gcp-devsecops"
  }

  network = {
    vpc_name               = "replace-with-staging-vpc"
    gke_subnet_cidr        = "10.20.0.0/20"
    management_subnet_cidr = "10.20.16.0/24"
    proxy_subnet_cidr      = "10.20.17.0/24"
    gke_pods_cidr          = "10.120.0.0/16"
    gke_services_cidr      = "10.130.0.0/20"
  }

  router = { name = "replace-with-staging-router" }
  nat = {
    name             = "replace-with-staging-nat"
    min_ports_per_vm = 64
  }
  firewall         = { internal_cidr = "10.20.0.0/16" }
  service_accounts = { secret_ids = [] }

  gke = {
    node_locations = ["replace-with-staging-zone-a", "replace-with-staging-zone-b", "replace-with-staging-zone-c"]
    node_pools = {
      system = {
        name         = "replace-with-staging-system-pool"
        machine_type = "e2-medium"
        min_count    = 1
        max_count    = 2
        disk_size_gb = 50
        labels       = { workload = "system" }
        taints       = [{ key = "workload", value = "system", effect = "NO_SCHEDULE" }]
      }
      general = {
        name         = "replace-with-staging-general-pool"
        machine_type = "e2-standard-4"
        min_count    = 2
        max_count    = 5
        disk_size_gb = 80
        labels       = { workload = "general" }
      }
      spot = {
        name         = "replace-with-staging-spot-pool"
        machine_type = "e2-standard-2"
        min_count    = 0
        max_count    = 2
        spot         = true
        labels       = { workload = "spot" }
        taints       = [{ key = "workload", value = "spot", effect = "NO_SCHEDULE" }]
      }
    }
    autoscaling = { enabled = true, profile = "BALANCED" }
    private_cluster = {
      enabled                 = true
      enable_private_endpoint = true
      master_authorized_cidrs = [{ cidr_block = "10.20.16.0/24", display_name = "management-subnet" }]
    }
    release_channel                 = "REGULAR"
    enable_gateway_api              = true
    enable_cloud_dns                = true
    enable_gcs_fuse_csi             = true
    enable_vertical_pod_autoscaling = true
    enable_managed_prometheus       = true
    binary_authorization_mode       = "DISABLED"
    deletion_protection             = true
    maintenance_start_time          = "2099-01-05T20:00:00Z"
    maintenance_end_time            = "2099-01-06T00:00:00Z"
    maintenance_recurrence          = "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR"
  }

  artifact_registry = { repository_id = "replace-with-staging-artifact-repository" }
  github            = { repository = "replace-with-owner/repository" }
  argocd = {
    chart_version = "replace-with-argocd-chart-version"
    git_repo_url  = "https://replace-with-git-repository"
  }
}

platform_config = {
  project_id   = "replace-with-prod-project-id"
  environment  = "prod"
  region       = "replace-with-prod-region"
  cluster_name = "replace-with-prod-cluster-name"

  labels = {
    environment      = "prod"
    cost_profile     = "high"
    availability     = "high"
    security_profile = "production"
    managed_by       = "terraform"
    platform         = "gcp-devsecops"
  }

  network = {
    vpc_name               = "replace-with-prod-vpc"
    gke_subnet_cidr        = "10.30.0.0/19"
    management_subnet_cidr = "10.30.32.0/24"
    proxy_subnet_cidr      = "10.30.33.0/24"
    gke_pods_cidr          = "10.140.0.0/16"
    gke_services_cidr      = "10.150.0.0/20"
  }

  router = { name = "replace-with-prod-router" }
  nat = {
    name             = "replace-with-prod-nat"
    min_ports_per_vm = 128
  }
  firewall         = { internal_cidr = "10.30.0.0/16" }
  service_accounts = { secret_ids = [] }

  gke = {
    node_locations = ["replace-with-prod-zone-a", "replace-with-prod-zone-b", "replace-with-prod-zone-c"]
    node_pools = {
      system = {
        name         = "replace-with-prod-system-pool"
        machine_type = "e2-standard-2"
        min_count    = 2
        max_count    = 4
        disk_size_gb = 80
        labels       = { workload = "system" }
        taints       = [{ key = "workload", value = "system", effect = "NO_SCHEDULE" }]
      }
      general = {
        name         = "replace-with-prod-general-pool"
        machine_type = "e2-standard-4"
        min_count    = 2
        max_count    = 8
        disk_size_gb = 100
        labels       = { workload = "general" }
      }
      spot = {
        name         = "replace-with-prod-spot-pool"
        machine_type = "e2-standard-2"
        min_count    = 0
        max_count    = 3
        disk_size_gb = 50
        spot         = true
        labels       = { workload = "spot" }
        taints       = [{ key = "workload", value = "spot", effect = "NO_SCHEDULE" }]
      }
    }
    autoscaling = { enabled = true, profile = "BALANCED" }
    private_cluster = {
      enabled                 = true
      enable_private_endpoint = true
      master_authorized_cidrs = [{ cidr_block = "10.30.32.0/24", display_name = "management-subnet" }]
    }
    release_channel                 = "STABLE"
    enable_gateway_api              = true
    enable_cloud_dns                = true
    enable_gcs_fuse_csi             = true
    enable_vertical_pod_autoscaling = true
    enable_managed_prometheus       = true
    binary_authorization_mode       = "PROJECT_SINGLETON_POLICY_ENFORCE"
    deletion_protection             = true
    maintenance_start_time          = "2099-01-05T20:00:00Z"
    maintenance_end_time            = "2099-01-06T00:00:00Z"
    maintenance_recurrence          = "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR"
  }

  artifact_registry = { repository_id = "replace-with-prod-artifact-repository" }
  github            = { repository = "replace-with-owner/repository" }
  argocd = {
    chart_version = "replace-with-argocd-chart-version"
    git_repo_url  = "https://replace-with-git-repository"
  }
}

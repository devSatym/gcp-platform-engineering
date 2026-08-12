module "project" {
  source     = "../project"
  project_id = var.config.project_id
  labels     = var.config.labels
}

module "networking" {
  source     = "../networking"
  project_id = var.config.project_id
  region     = var.config.region
  vpc_name   = var.config.network.vpc_name
  labels     = var.config.labels

  gke_subnet_cidr        = var.config.network.gke_subnet_cidr
  management_subnet_cidr = var.config.network.management_subnet_cidr
  proxy_subnet_cidr      = var.config.network.proxy_subnet_cidr
  gke_pods_cidr          = var.config.network.gke_pods_cidr
  gke_services_cidr      = var.config.network.gke_services_cidr

  depends_on = [module.project]
}

module "cloud_router" {
  source      = "../cloud-router"
  project_id  = var.config.project_id
  region      = var.config.region
  router_name = var.config.router.name
  vpc_name    = module.networking.vpc_name

  depends_on = [module.networking]
}

module "nat" {
  source           = "../nat"
  project_id       = var.config.project_id
  region           = var.config.region
  nat_name         = var.config.nat.name
  router_name      = module.cloud_router.router_name
  min_ports_per_vm = var.config.nat.min_ports_per_vm

  depends_on = [module.cloud_router]
}

module "firewall" {
  source        = "../firewall"
  project_id    = var.config.project_id
  vpc_name      = module.networking.vpc_name
  internal_cidr = var.config.firewall.internal_cidr

  depends_on = [module.networking]
}

module "service_accounts" {
  source     = "../service-accounts"
  project_id = var.config.project_id
  labels     = var.config.labels
  secret_ids = var.config.service_accounts.secret_ids

  depends_on = [module.project]
}

module "gke" {
  source = "../gke"

  project_id    = var.config.project_id
  cluster_name  = var.config.cluster_name
  region        = var.config.region
  location_type = var.config.gke.location_type
  labels        = var.config.labels

  node_locations                = var.config.gke.node_locations
  network_name                  = module.networking.vpc_name
  subnetwork_name               = module.networking.gke_subnet_name
  pods_secondary_range_name     = module.networking.gke_pods_range_name
  services_secondary_range_name = module.networking.gke_services_range_name
  node_service_account          = module.service_accounts.gke_node_sa_email
  node_pools                    = var.config.gke.node_pools
  autoscaling                   = var.config.gke.autoscaling
  private_cluster               = var.config.gke.private_cluster
  release_channel               = var.config.gke.release_channel

  enable_workload_identity         = var.config.gke.enable_workload_identity
  enable_shielded_nodes            = var.config.gke.enable_shielded_nodes
  enable_gateway_api               = var.config.gke.enable_gateway_api
  enable_cloud_dns                 = var.config.gke.enable_cloud_dns
  enable_gcs_fuse_csi              = var.config.gke.enable_gcs_fuse_csi
  enable_vertical_pod_autoscaling  = var.config.gke.enable_vertical_pod_autoscaling
  enable_managed_prometheus        = var.config.gke.enable_managed_prometheus
  logging_components               = var.config.gke.logging_components
  monitoring_components            = var.config.gke.monitoring_components
  binary_authorization_mode        = var.config.gke.binary_authorization_mode
  deletion_protection              = var.config.gke.deletion_protection
  maintenance_start_time           = var.config.gke.maintenance_start_time
  maintenance_end_time             = var.config.gke.maintenance_end_time
  maintenance_recurrence           = var.config.gke.maintenance_recurrence
  bootstrap_node_machine_type      = var.config.gke.bootstrap_node_machine_type
  bootstrap_node_disk_type         = var.config.gke.bootstrap_node_disk_type
  bootstrap_node_disk_size_gb      = var.config.gke.bootstrap_node_disk_size_gb
  datapath_provider                = var.config.gke.datapath_provider
  enable_network_policy            = var.config.gke.enable_network_policy
  enable_advanced_datapath_metrics = var.config.gke.enable_advanced_datapath_metrics
  enable_datapath_relay            = var.config.gke.enable_datapath_relay
  enable_http_load_balancing       = var.config.gke.enable_http_load_balancing
  enable_hpa_addon                 = var.config.gke.enable_hpa_addon

  depends_on = [module.networking, module.service_accounts, module.nat]
}

module "artifact_registry" {
  source = "../artifact-registry"

  project_id              = var.config.project_id
  region                  = var.config.region
  repository_id           = var.config.artifact_registry.repository_id
  gke_node_sa_email       = module.service_accounts.gke_node_sa_email
  github_actions_sa_email = module.service_accounts.github_actions_sa_email
  labels                  = var.config.labels

  depends_on = [module.project]
}

module "github_wif" {
  source = "../github-wif"

  project_id              = var.config.project_id
  github_repo             = var.config.github.repository
  github_actions_sa_email = module.service_accounts.github_actions_sa_email

  depends_on = [module.project]
}

moved {
  from = google_container_node_pool.system
  to   = google_container_node_pool.pools["system"]
}

moved {
  from = google_container_node_pool.general
  to   = google_container_node_pool.pools["general"]
}

moved {
  from = google_container_node_pool.spot
  to   = google_container_node_pool.pools["spot"]
}

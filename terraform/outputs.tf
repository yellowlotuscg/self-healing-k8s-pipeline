output "cluster_name" {
  description = "Name of the kind cluster."
  value       = kind_cluster.this.name
}

output "kubeconfig_path" {
  description = "Path kind wrote the kubeconfig to (merged into ~/.kube/config)."
  value       = kind_cluster.this.kubeconfig_path
}

output "cluster_endpoint" {
  description = "API server endpoint."
  value       = kind_cluster.this.endpoint
}

output "monitoring_installed" {
  description = "Whether the kube-prometheus-stack was installed."
  value       = var.install_monitoring
}

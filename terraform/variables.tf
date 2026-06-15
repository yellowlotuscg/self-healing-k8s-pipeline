variable "cluster_name" {
  description = "Name of the local kind cluster."
  type        = string
  default     = "self-healing-demo"
}

variable "monitoring_namespace" {
  description = "Namespace for the kube-prometheus-stack."
  type        = string
  default     = "monitoring"
}

variable "install_monitoring" {
  description = "Whether to install the kube-prometheus-stack via Helm."
  type        = bool
  default     = true
}

variable "kube_prometheus_stack_version" {
  description = "Chart version for kube-prometheus-stack. Pinned on purpose."
  type        = string
  default     = "62.3.0"
}

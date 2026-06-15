# ----------------------------------------------------------------------------
# Local kind cluster + monitoring stack, all via Terraform.
#
# This deliberately targets LOCAL kind (no cloud, no cost) but mirrors how I'd
# stand up the same thing on EKS: cluster as code, providers pinned, monitoring
# installed declaratively via Helm. Swap the kind_cluster resource for the
# terraform-aws-modules/eks module and the rest barely changes.
#
# terraform isn't installed in the build env, so this is validated-by-review.
# ----------------------------------------------------------------------------

# 1) The kind cluster itself. The extraPortMappings expose the ingress-nginx
#    controller on host ports 80/443 so the Ingress in k8s/ingress.yaml works.
resource "kind_cluster" "this" {
  name           = var.cluster_name
  wait_for_ready = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"

      # Label so the ingress-nginx "kind" manifest schedules its controller here.
      kubeadm_config_patches = [
        "kind: InitConfiguration\nnodeRegistration:\n  kubeletExtraArgs:\n    node-labels: \"ingress-ready=true\"\n"
      ]

      extra_port_mappings {
        container_port = 80
        host_port      = 80
        protocol       = "TCP"
      }
      extra_port_mappings {
        container_port = 443
        host_port      = 443
        protocol       = "TCP"
      }
    }

    # Two workers so PodDisruptionBudgets, topology spread, and drains are
    # actually meaningful (a single-node cluster can't demonstrate spread).
    node {
      role = "worker"
    }
    node {
      role = "worker"
    }
  }
}

# 2) Wire the kubernetes + helm providers to the cluster kind just created.
#    Reading the attributes off the resource keeps it a single `apply`.
provider "kubernetes" {
  host                   = kind_cluster.this.endpoint
  client_certificate     = kind_cluster.this.client_certificate
  client_key             = kind_cluster.this.client_key
  cluster_ca_certificate = kind_cluster.this.cluster_ca_certificate
}

provider "helm" {
  kubernetes {
    host                   = kind_cluster.this.endpoint
    client_certificate     = kind_cluster.this.client_certificate
    client_key             = kind_cluster.this.client_key
    cluster_ca_certificate = kind_cluster.this.cluster_ca_certificate
  }
}

# 3) Monitoring namespace.
resource "kubernetes_namespace" "monitoring" {
  count = var.install_monitoring ? 1 : 0

  metadata {
    name = var.monitoring_namespace
  }
}

# 4) kube-prometheus-stack via Helm, fed the same values file `make
#    observability` uses so the two paths can't drift.
resource "helm_release" "kube_prometheus_stack" {
  count = var.install_monitoring ? 1 : 0

  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.kube_prometheus_stack_version
  namespace  = kubernetes_namespace.monitoring[0].metadata[0].name

  # Reuse the checked-in values so Terraform and Helm-by-hand stay identical.
  values = [file("${path.module}/../observability/values-kube-prometheus-stack.yaml")]

  # The CRDs are large; give Helm room.
  timeout = 600
}

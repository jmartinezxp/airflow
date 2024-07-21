# output "eks_service_role_arn" {
#   value = aws_iam_role.eks_service_role.arn
# }

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane."
  value       = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Security group ids attached to the cluster control plane."
  value       = module.eks.cluster_security_group_id
}


output "eks_all" {
  value = module.eks
}
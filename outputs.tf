output "frontend_url" {
  description = "The DNS name of the external load balancer to access the Frontend"
  value       = "http://${aws_lb.ext_alb.dns_name}"
}
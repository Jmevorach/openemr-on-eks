# OpenEMR EKS Deployment Configuration
# Copy this file to terraform.tfvars and customize for your environment

# Basic Configuration
aws_region   = "us-west-2" # Change to your preferred region
environment  = "production"
cluster_name = "openemr-eks"

# Kubernetes Configuration
kubernetes_version = "1.33"

# Network Configuration
vpc_cidr        = "10.0.0.0/16"
private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

# Database Configuration (Aurora Serverless V2)
aurora_min_capacity = 0.5 # Minimum ACUs (always running cost: ~$43/month)
aurora_max_capacity = 16  # Maximum ACUs for scaling

# Cache Configuration (Valkey Serverless)
redis_max_data_storage    = 20   # GB
redis_max_ecpu_per_second = 5000 # ECPUs

# Security Configuration
enable_public_access = true # Set to false for maximum security
# allowed_cidr_blocks = ["203.0.113.0/24"]  # Uncomment to specify custom IPs
enable_waf = true

# Domain Configuration (Optional)
# domain_name = "openemr.yourdomain.com"  # Leave empty for LoadBalancer access only

# Backup and Retention
backup_retention_days     = 30  # RDS backup retention
alb_logs_retention_days   = 90  # ALB access logs in S3
app_logs_retention_days   = 30  # Application logs in CloudWatch
audit_logs_retention_days = 365 # Audit logs for compliance

# EKS Auto Mode Configuration
# Auto Mode is enabled by default - no additional configuration needed

# Cost Optimization Settings
# These settings balance cost and performance for different organization sizes:

# Small Clinic (10-50 users) - ~$369/month
# aurora_min_capacity = 0.5
# aurora_max_capacity = 4
# redis_max_data_storage = 2
# redis_max_ecpu_per_second = 1000

# Medium Practice (50-200 users) - ~$753/month
# aurora_min_capacity = 0.5
# aurora_max_capacity = 8
# redis_max_data_storage = 5
# redis_max_ecpu_per_second = 2500

# Large Hospital (200-1000 users) - ~$2,119/month
# aurora_min_capacity = 0.5
# aurora_max_capacity = 16
# redis_max_data_storage = 15
# redis_max_ecpu_per_second = 5000

# OpenEMR Autoscaling Configuration
# Customize these values based on your organization size and usage patterns
# See docs/AUTOSCALING_GUIDE.md for detailed guidance

# Default Configuration (Balanced - Recommended for most organizations)
openemr_min_replicas                     = 2   # Minimum replicas for high availability
openemr_max_replicas                     = 10  # Maximum replicas for peak load
openemr_cpu_utilization_threshold        = 70  # CPU percentage to trigger scaling
openemr_memory_utilization_threshold     = 80  # Memory percentage to trigger scaling
openemr_scale_down_stabilization_seconds = 300 # Wait 5 minutes before scaling down
openemr_scale_up_stabilization_seconds   = 60  # Wait 1 minute before scaling up

# Small Clinic Configuration (10-50 users)
# openemr_min_replicas                    = 2
# openemr_max_replicas                    = 4
# openemr_cpu_utilization_threshold       = 75
# openemr_memory_utilization_threshold    = 80
# openemr_scale_down_stabilization_seconds = 600  # 10 minutes
# openemr_scale_up_stabilization_seconds   = 60   # 1 minute

# Medium Practice Configuration (50-200 users)
# openemr_min_replicas                    = 3
# openemr_max_replicas                    = 8
# openemr_cpu_utilization_threshold       = 70
# openemr_memory_utilization_threshold    = 80
# openemr_scale_down_stabilization_seconds = 300  # 5 minutes
# openemr_scale_up_stabilization_seconds   = 60   # 1 minute

# Large Hospital Configuration (200-1000+ users)
# openemr_min_replicas                    = 5
# openemr_max_replicas                    = 20
# openemr_cpu_utilization_threshold       = 60
# openemr_memory_utilization_threshold    = 75
# openemr_scale_down_stabilization_seconds = 300  # 5 minutes
# openemr_scale_up_stabilization_seconds   = 45   # 45 seconds

# Performance Priority Configuration (Lower thresholds, more replicas)
# openemr_min_replicas                    = 4
# openemr_max_replicas                    = 12
# openemr_cpu_utilization_threshold       = 60
# openemr_memory_utilization_threshold    = 70
# openemr_scale_down_stabilization_seconds = 600  # 10 minutes
# openemr_scale_up_stabilization_seconds   = 45   # 45 seconds

# Cost Priority Configuration (Higher thresholds, fewer replicas)
# openemr_min_replicas                    = 2
# openemr_max_replicas                    = 6
# openemr_cpu_utilization_threshold       = 80
# openemr_memory_utilization_threshold    = 85
# openemr_scale_down_stabilization_seconds = 180  # 3 minutes
# openemr_scale_up_stabilization_seconds   = 90   # 1.5 minutes

# OpenEMR Application Configuration
openemr_version = "7.0.3" # OpenEMR version to deploy

# OpenEMR Feature Configuration (SECURITY: Disabled by default)
# Only enable these features if specifically needed for your use case
enable_openemr_api    = false # Enable REST API and FHIR endpoints
enable_patient_portal = false # Enable patient portal functionality

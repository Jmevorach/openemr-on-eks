# Testing-specific Terraform variables
# This file overrides production defaults for testing purposes

# Disable deletion protection for testing (enables terraform destroy)
rds_deletion_protection = false

# Reduce backup retention for testing (faster cleanup)
backup_retention_days = 1

# Reduce Aurora capacity for testing (cost optimization)
aurora_min_capacity = 0.5
aurora_max_capacity = 4

# Disable WAF for testing (simplified setup)
enable_waf = false

# Enable public access for testing (easier debugging)
enable_public_access = true

# Environment tag for testing
environment = "testing"

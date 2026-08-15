# ==========================================
# Database Subnet Groups
# ==========================================

# 1. RDS Subnet Group
resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "rds-subnet-group"
  subnet_ids = [aws_subnet.data_private_a.id, aws_subnet.data_private_b.id]
  tags       = { Name = "RDS Subnet Group" }
}

# 2. Redis Subnet Group
resource "aws_elasticache_subnet_group" "redis_subnet_group" {
  name       = "redis-subnet-group"
  subnet_ids = [aws_subnet.data_private_a.id, aws_subnet.data_private_b.id]
  tags       = { Name = "Redis Subnet Group" }
}

# ==========================================
# Relational Database Service (RDS - MySQL)
# ==========================================

resource "aws_db_instance" "main_rds" {
  identifier              = "main-rds-db"
  engine                  = "mysql"
  engine_version          = "8.0"
  instance_class          = "db.t3.micro" 
  allocated_storage       = 20

  db_name                 = "workshopdb"
  username                = "admin"
  password                = "Admin12345!" 

  # --- Requirements from Task 4.1 ---
  multi_az                = true
  storage_encrypted       = true
  backup_retention_period = 7
  # ----------------------------------

  db_subnet_group_name    = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids  = [aws_security_group.data_tier_sg.id]
  
  skip_final_snapshot     = true 
  
  tags = { Name = "Primary-RDS" }
}

# ==========================================
# ElastiCache (Redis)
# ==========================================

resource "aws_elasticache_replication_group" "main_redis" {
  replication_group_id          = "main-redis-cluster"
  description                   = "Redis cluster for app caching"
  engine                        = "redis"
  node_type                     = "cache.t3.micro"
  
  # --- Requirements from Task 4.1 ---
  num_cache_clusters            = 2    
  automatic_failover_enabled    = true 
  
  at_rest_encryption_enabled    = true
  transit_encryption_enabled    = true
  # ----------------------------------

  subnet_group_name             = aws_elasticache_subnet_group.redis_subnet_group.name
  security_group_ids            = [aws_security_group.data_tier_sg.id]
  
  tags = { Name = "Redis-Cluster" }
}
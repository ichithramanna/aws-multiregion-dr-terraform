# ─── Aurora Global Database ──────────────────────────────────────
# Global wrapper that links primary + DR clusters together
# Engine and version defined here ONCE — both clusters inherit it
resource "aws_rds_global_cluster" "main" {
  global_cluster_identifier = "three-tier-global-db"
  engine                    = "aurora-mysql"
  engine_version            = "8.0.mysql_aurora.3.08.2"
  database_name             = "appdb"
  deletion_protection       = false  # set true in real production
}

# ─── Primary DB Subnet Group ─────────────────────────────────────
# Tells Aurora WHICH subnets to place the DB in (always private/db subnets)
resource "aws_db_subnet_group" "primary" {
  name       = "primary-db-subnet-group"
  subnet_ids = [aws_subnet.db_a.id, aws_subnet.db_b.id]

  tags = {
    Name = "primary-db-subnet-group"
  }
}

# ─── Primary Aurora Cluster ──────────────────────────────────────
# The actual database cluster in us-east-1
# This is the WRITER — app reads and writes here
resource "aws_rds_cluster" "primary" {
  cluster_identifier        = "three-tier-primary-cluster"
  global_cluster_identifier = aws_rds_global_cluster.main.id  # joins global DB
  engine                    = aws_rds_global_cluster.main.engine
  engine_version            = aws_rds_global_cluster.main.engine_version
  database_name             = "appdb"
  master_username           = "admin"
  master_password           = var.db_password   # from terraform.tfvars
  db_subnet_group_name      = aws_db_subnet_group.primary.name
  vpc_security_group_ids    = [aws_security_group.rds_sg.id]
  skip_final_snapshot       = true  # set false in real production

  tags = {
    Name = "primary-aurora-cluster"
  }
}

# ─── Primary Aurora Instance ─────────────────────────────────────
# The COMPUTE node that runs the database
# db.t3.medium = burstable, cheapest Aurora Global DB supports
resource "aws_rds_cluster_instance" "primary" {
  identifier           = "three-tier-primary-instance"
  cluster_identifier   = aws_rds_cluster.primary.id
  instance_class       = "db.r6g.large"  
  engine               = aws_rds_cluster.primary.engine
  engine_version       = aws_rds_cluster.primary.engine_version
  db_subnet_group_name = aws_db_subnet_group.primary.name

  tags = {
    Name = "primary-aurora-instance"
  }
}

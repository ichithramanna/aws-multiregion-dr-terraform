resource "aws_db_subnet_group" "dr" {
  provider   = aws.dr
  name       = "dr-db-subnet-group"
  subnet_ids = [aws_subnet.dr_db_a.id, aws_subnet.dr_db_b.id]
  tags       = { Name = "dr-db-subnet-group" }
}

resource "aws_rds_cluster" "dr" {
  provider                  = aws.dr
  cluster_identifier        = "three-tier-dr-cluster"
  global_cluster_identifier = aws_rds_global_cluster.main.id
  engine                    = aws_rds_global_cluster.main.engine
  engine_version            = aws_rds_global_cluster.main.engine_version
  db_subnet_group_name      = aws_db_subnet_group.dr.name
  vpc_security_group_ids    = [aws_security_group.dr_rds_sg.id]
  skip_final_snapshot       = true
  tags                      = { Name = "dr-aurora-cluster" }
  depends_on                = [aws_rds_cluster.primary]
}

resource "aws_rds_cluster_instance" "dr" {
  provider             = aws.dr
  identifier           = "three-tier-dr-instance"
  cluster_identifier   = aws_rds_cluster.dr.id
  instance_class       = "db.r6g.large"
  engine               = aws_rds_cluster.dr.engine
  db_subnet_group_name = aws_db_subnet_group.dr.name
  tags                 = { Name = "dr-aurora-instance" }
}

resource "aws_db_instance" "marketmate_db" {
  identifier             = "marketmate-db"
  instance_class         = "db.t3.micro"
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.marketmate_db_subnet.name
  availability_zone      = "eu-central-1a"

  snapshot_identifier = "marketmate-db-pre-destroy-snapshot"

  # prevents deletion via console or API
  deletion_protection = false

  # snapshot management
  skip_final_snapshot       = true
  final_snapshot_identifier = "marketmate-db-pre-destroy-snapshot"

  # prevents 'terraform destroy'
  lifecycle {
    prevent_destroy = false
  }
}

# ─── AMI lookup — Ubuntu 24.04 LTS (Noble) ────────────────────────────────────

data "aws_ami" "ubuntu_noble" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# ─── S3 bucket for bootstrap script ───────────────────────────────────────────
# The rendered userdata.sh exceeds EC2's 16 KB user_data limit.
# We store it in S3 and have a tiny launcher script (~300 bytes) fetch it.

resource "random_id" "bootstrap" {
  byte_length = 4
}

resource "aws_s3_bucket" "bootstrap" {
  bucket        = "${var.name_prefix}-bootstrap-${random_id.bootstrap.hex}"
  force_destroy = true

  tags = merge(var.tags, { Name = "${var.name_prefix}-bootstrap" })
}

resource "aws_s3_bucket_public_access_block" "bootstrap" {
  bucket                  = aws_s3_bucket.bootstrap.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Upload the fully-rendered bootstrap script to S3
resource "aws_s3_object" "bootstrap_script" {
  bucket = aws_s3_bucket.bootstrap.id
  key    = "bootstrap.sh"
  content = templatefile("${path.module}/templates/userdata.sh.tpl", {
    weka_backend            = var.weka_backend
    weka_nfs_server         = var.weka_nfs_server
    weka_password_secret_id = var.weka_password_secret_id
    lambda_status_name      = var.lambda_status_name
    aws_region              = var.aws_region
    devstack_branch         = var.devstack_branch
    driver_branch           = var.driver_branch
    admin_password          = var.admin_password
  })
  content_type = "text/x-shellscript"
}

# ─── IAM Role for DevStack instance ───────────────────────────────────────────

resource "aws_iam_role" "devstack" {
  name        = "${var.name_prefix}-devstack-role"
  description = "IAM role for the DevStack EC2 instance"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(var.tags, { Name = "${var.name_prefix}-devstack-role" })
}

resource "aws_iam_role_policy" "devstack_secrets" {
  name = "${var.name_prefix}-devstack-secrets"
  role = aws_iam_role.devstack.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadWekaAdminPassword"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
        ]
        Resource = [
          var.weka_password_secret_id,
          "${var.weka_password_secret_id}-??????",
        ]
      },
      {
        Sid    = "ReadWekaAdminPasswordByPath"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
        ]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:*:secret:${var.name_prefix}*"
      },
    ]
  })
}

resource "aws_iam_role_policy" "devstack_lambda" {
  name = "${var.name_prefix}-devstack-lambda"
  role = aws_iam_role.devstack.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "InvokeWekaStatusLambda"
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = "arn:aws:lambda:${var.aws_region}:*:function:${var.lambda_status_name}"
    }]
  })
}

# Allow the instance to fetch its own bootstrap script from S3
resource "aws_iam_role_policy" "devstack_s3" {
  name = "${var.name_prefix}-devstack-s3"
  role = aws_iam_role.devstack.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "GetBootstrapScript"
      Effect   = "Allow"
      Action   = ["s3:GetObject"]
      Resource = "${aws_s3_bucket.bootstrap.arn}/bootstrap.sh"
    }]
  })
}

resource "aws_iam_instance_profile" "devstack" {
  name = "${var.name_prefix}-devstack-profile"
  role = aws_iam_role.devstack.name

  tags = var.tags
}

# ─── EC2 Instance ─────────────────────────────────────────────────────────────

resource "aws_instance" "devstack" {
  ami                    = data.aws_ami.ubuntu_noble.id
  instance_type          = var.instance_type
  subnet_id              = var.devstack_subnet_id
  vpc_security_group_ids = [var.devstack_sg_id]
  key_name               = var.key_pair_name
  iam_instance_profile   = aws_iam_instance_profile.devstack.name

  associate_public_ip_address = true
  source_dest_check           = false # Allow Nova VM floating IPs (172.24.4.0/24) to reach Weka NFS gateway

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size_gb
    delete_on_termination = true
    encrypted             = true

    tags = merge(var.tags, { Name = "${var.name_prefix}-devstack-root" })
  }

  # Minimal launcher — downloads the full bootstrap script from S3 and runs it.
  # Kept well under the 16 KB EC2 user_data limit.
  user_data = <<-USERDATA
    #!/bin/bash
    set -ex
    exec > >(tee -a /var/log/devstack-bootstrap.log) 2>&1
    echo "=== Launcher: $(date) ==="
    # Install AWS CLI v2 — awscli apt package was removed from Ubuntu 24.04
    if ! command -v aws &>/dev/null; then
      apt-get update -qq
      apt-get install -y -qq unzip curl
      curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
        -o /tmp/awscliv2.zip
      unzip -q /tmp/awscliv2.zip -d /tmp/
      /tmp/aws/install
      rm -rf /tmp/aws /tmp/awscliv2.zip
    fi
    aws s3 cp s3://${aws_s3_bucket.bootstrap.id}/bootstrap.sh /root/bootstrap.sh \
      --region ${var.aws_region}
    chmod +x /root/bootstrap.sh
    exec /root/bootstrap.sh
  USERDATA

  # The instance must not be replaced if the bootstrap script changes
  # (re-bootstrapping from scratch takes ~45 min).
  depends_on = [aws_s3_object.bootstrap_script]

  tags = merge(var.tags, { Name = "${var.name_prefix}-devstack" })

  lifecycle {
    ignore_changes = [user_data, ami]
  }
}

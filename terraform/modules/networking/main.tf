# ─── VPC ──────────────────────────────────────────────────────────────────────

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, { Name = "${var.name_prefix}-vpc" })
}

# ─── Internet Gateway ─────────────────────────────────────────────────────────

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, { Name = "${var.name_prefix}-igw" })
}

# ─── Subnets ──────────────────────────────────────────────────────────────────

# Weka backend subnet (primary AZ)
resource "aws_subnet" "weka" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.weka_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = merge(var.tags, { Name = "${var.name_prefix}-weka-subnet" })
}

# DevStack subnet (same AZ as Weka for minimal latency)
resource "aws_subnet" "devstack" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.devstack_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = merge(var.tags, { Name = "${var.name_prefix}-devstack-subnet" })
}

# ALB second subnet (different AZ — ALB requires multi-AZ)
resource "aws_subnet" "alb" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.alb_subnet_cidr
  availability_zone       = var.alb_availability_zone
  map_public_ip_on_launch = false

  tags = merge(var.tags, { Name = "${var.name_prefix}-alb-subnet" })
}

# ─── Route Table ──────────────────────────────────────────────────────────────

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-rt" })
}

resource "aws_route_table_association" "weka" {
  subnet_id      = aws_subnet.weka.id
  route_table_id = aws_route_table.main.id
}

resource "aws_route_table_association" "devstack" {
  subnet_id      = aws_subnet.devstack.id
  route_table_id = aws_route_table.main.id
}

resource "aws_route_table_association" "alb" {
  subnet_id      = aws_subnet.alb.id
  route_table_id = aws_route_table.main.id
}

# ─── Security Groups ──────────────────────────────────────────────────────────
#
# NOTE: weka_sg references devstack_sg and vice-versa.
# We avoid circular dependency by using VPC CIDR for cross-SG rules
# rather than SG-to-SG references, which is safe within a private VPC.

# Weka cluster security group
resource "aws_security_group" "weka" {
  name        = "${var.name_prefix}-weka-sg"
  description = "Security group for Weka backend cluster nodes"
  vpc_id      = aws_vpc.main.id

  tags = merge(var.tags, { Name = "${var.name_prefix}-weka-sg" })

  # CRITICAL: Self-reference ingress — Weka nodes must communicate freely
  # with each other on all ports. Without this rule the cluster will never
  # form a quorum and clusterization will fail.
  ingress {
    description = "Weka inter-node communication (self-reference, all protocols)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # Weka REST API accessible from within the VPC (includes DevStack node)
  ingress {
    description = "Weka REST API from VPC (includes DevStack)"
    from_port   = 14000
    to_port     = 14000
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Weka REST API from admin CIDR — required for NLB TCP passthrough
  # (NLB preserves client source IP, so target SG must allow admin_cidr directly)
  ingress {
    description = "Weka REST API from admin CIDR (external NLB access)"
    from_port   = 14000
    to_port     = 14000
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  # SSH access for administration
  ingress {
    description = "SSH from admin CIDR"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  # Weka HTTPS management UI
  ingress {
    description = "Weka HTTPS UI from admin CIDR"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  # Full outbound access (package installs, Weka get.io download, AWS APIs)
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# DevStack security group
resource "aws_security_group" "devstack" {
  name        = "${var.name_prefix}-devstack-sg"
  description = "Security group for the DevStack OpenStack instance"
  vpc_id      = aws_vpc.main.id

  tags = merge(var.tags, { Name = "${var.name_prefix}-devstack-sg" })

  # SSH
  ingress {
    description = "SSH from admin CIDR"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  # Horizon (HTTP)
  ingress {
    description = "Horizon dashboard HTTP from admin CIDR"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  # Horizon (HTTPS)
  ingress {
    description = "Horizon dashboard HTTPS from admin CIDR"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  # Keystone auth
  ingress {
    description = "Keystone identity service from admin CIDR"
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  # Manila share service
  ingress {
    description = "Manila share service API from admin CIDR"
    from_port   = 8786
    to_port     = 8786
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  # All traffic from within VPC — required for:
  # - WekaFS POSIX client ↔ Weka backend communication
  # - OpenStack service-to-service (Nova metadata, etc.)
  ingress {
    description = "All traffic from VPC (Weka client + OpenStack services)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  # Self-reference for internal DevStack service communication
  ingress {
    description = "DevStack internal service communication (self-reference)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # Full outbound
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ALB security group (used by the Weka ALB)
resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb-sg"
  description = "Security group for the Weka Application Load Balancer"
  vpc_id      = aws_vpc.main.id

  tags = merge(var.tags, { Name = "${var.name_prefix}-alb-sg" })

  # HTTPS Weka UI
  ingress {
    description = "HTTPS Weka UI from admin CIDR"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  # Weka REST API — from VPC (DevStack) and admin
  ingress {
    description = "Weka REST API from VPC and admin"
    from_port   = 14000
    to_port     = 14000
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr, var.vpc_cidr]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

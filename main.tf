resource "aws_vpc" "web_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "web_vpc"
  }
  enable_dns_hostnames = true
  enable_dns_support   = true
}

resource "aws_subnet" "web_subnet-private" {
  count = length(var.availability_zones)

  cidr_block        = "10.0.${count.index + 1}.0/24"
  availability_zone = var.availability_zones[count.index]
  vpc_id            = aws_vpc.web_vpc.id
  tags = {
    Name = "web_subnet-private"
  }
}

resource "aws_subnet" "web_subnet-public" {
  count = length(var.availability_zones)

  cidr_block              = "10.0.${count.index + 4}.0/24"
  vpc_id                  = aws_vpc.web_vpc.id
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name = "web_subnet-public"
  }
}

resource "aws_internet_gateway" "web_igw" {
  vpc_id = aws_vpc.web_vpc.id
  tags = {
    Name = "web_igw"
  }
}

resource "aws_route_table" "web_rt" {
  vpc_id = aws_vpc.web_vpc.id
  tags = {
    Name = "web_rt"
  }
}

resource "aws_route" "default_route" {
  gateway_id             = aws_internet_gateway.web_igw.id
  destination_cidr_block = "0.0.0.0/0"
  route_table_id         = aws_route_table.web_rt.id
}

resource "aws_route_table_association" "rt_assoc" {
  count          = 3
  route_table_id = aws_route_table.web_rt.id
  subnet_id      = aws_subnet.web_subnet-public[count.index].id
}

resource "aws_eip" "nat_gateway_eip" {
  vpc = true

  tags = {
    Name = "web eip"
  }
}

resource "aws_nat_gateway" "web_nat_gateway" {
  allocation_id = aws_eip.nat_gateway_eip.id
  subnet_id     = element(aws_subnet.web_subnet-public[*].id, 0)

  depends_on = [
    aws_internet_gateway.web_igw,
  ]

  tags = {
    Name = "web NAT"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.web_vpc.id
}

resource "aws_route" "private_route" {
  route_table_id         = aws_route_table.private_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.web_nat_gateway.id
}

resource "aws_route_table_association" "private_route_association" {
  count          = 3
  subnet_id      = aws_subnet.web_subnet-private[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

resource "aws_security_group" "web_sg" {
  name        = "web_sg"
  vpc_id      = aws_vpc.web_vpc.id
  description = "security group for develpment"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["49.43.7.34/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_key_pair" "web_auth" {
  key_name   = "web_key"
  public_key = file("~/.ssh/kstubhkey.pub")
}

data "aws_ami" "server_ami" {
  most_recent = true
  owners      = ["137112412989"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.3.20240117.0-kernel-6.1-x86_64"]
  }
}

resource "aws_instance" "web_node" {
  count                  = 3
  instance_type          = "t2.micro"
  ami                    = data.aws_ami.server_ami.id
  key_name               = aws_key_pair.web_auth.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  subnet_id              = element(aws_subnet.web_subnet-private[*].id, count.index)
  user_data              = file("userdata.tpl")

  root_block_device {
    volume_size = 10
  }

  tags = {
    Name = "web_node"
  }
}

resource "aws_lb" "web-alb" {
  name               = "web-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = aws_subnet.web_subnet-public[*].id
}

resource "aws_lb_target_group" "web_tg" {
  name_prefix = "my-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.web_vpc.id

  health_check {
    enabled = true
    path    = "/"
    port    = 80

    healthy_threshold   = 2
    interval            = 30
    protocol            = "HTTP"
    timeout             = 6
    unhealthy_threshold = 2
    matcher             = "200-299"
  }

  target_type = "instance"

  tags = {
    Name = "web_tg"
  }
}

resource "aws_lb_listener" "web-listener" {
  load_balancer_arn = aws_lb.web-alb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg.id
  }
  depends_on = [
    aws_lb_target_group.web_tg,
    aws_lb.web-alb,
  ]
  tags = {
    Name = "web-listener"
  }
}

resource "aws_lb_target_group_attachment" "web-tg-attach" {
  count = 3
  target_group_arn = aws_lb_target_group.web_tg.arn
  target_id        = element(aws_instance.web_node[*].id, count.index)
  port             = 80
}


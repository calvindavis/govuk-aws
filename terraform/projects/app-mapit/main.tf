/**
* ## Project: app-mapit
*
* Mapit node
*/
variable "aws_environment" {
  type        = "string"
  description = "AWS environment"
}

variable "aws_region" {
  type        = "string"
  description = "AWS region"
  default     = "eu-west-1"
}

variable "stackname" {
  type        = "string"
  description = "Stackname"
}

variable "instance_ami_filter_name" {
  type        = "string"
  description = "Name to use to find AMI images"
  default     = ""
}

variable "mapit_1_subnet" {
  type        = "string"
  description = "Name of the subnet to place the mapit instance 1 and EBS volume"
}

variable "mapit_2_subnet" {
  type        = "string"
  description = "Name of the subnet to place the mapit instance 1 and EBS volume"
}

variable "elb_internal_certname" {
  type        = "string"
  description = "The ACM cert domain name to find the ARN of"
}

variable "instance_type" {
  type        = "string"
  description = "The type of EC2 instance to use for both ASGs."
  default     = "t2.medium"
}

# Resources
# --------------------------------------------------------------
terraform {
  backend          "s3"             {}
  required_version = "= 0.11.6"
}

provider "aws" {
  region  = "${var.aws_region}"
  version = "1.14.0"
}

data "aws_acm_certificate" "elb_internal_cert" {
  domain   = "${var.elb_internal_certname}"
  statuses = ["ISSUED"]
}

resource "aws_elb" "mapit_elb" {
  name            = "${var.stackname}-mapit-internal"
  subnets         = ["${data.terraform_remote_state.infra_networking.private_subnet_ids}"]
  security_groups = ["${data.terraform_remote_state.infra_security_groups.sg_mapit_elb_id}"]
  internal        = "true"

  access_logs {
    bucket        = "${data.terraform_remote_state.infra_monitoring.aws_logging_bucket_id}"
    bucket_prefix = "elb/${var.stackname}-mapit-internal-elb"
    interval      = 60
  }

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 443
    lb_protocol       = "https"

    ssl_certificate_id = "${data.aws_acm_certificate.elb_internal_cert.arn}"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3

    target   = "TCP:80"
    interval = 30
  }

  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400

  tags = "${map("Name", "${var.stackname}-mapit-internal", "Project", var.stackname, "aws_migration", "mapit", "aws_environment", var.aws_environment)}"
}

resource "aws_route53_record" "mapit_service_record" {
  zone_id = "${data.terraform_remote_state.infra_stack_dns_zones.internal_zone_id}"
  name    = "mapit.${data.terraform_remote_state.infra_stack_dns_zones.internal_domain_name}"
  type    = "A"

  alias {
    name                   = "${aws_elb.mapit_elb.dns_name}"
    zone_id                = "${aws_elb.mapit_elb.zone_id}"
    evaluate_target_health = true
  }
}

module "mapit-1" {
  source                        = "../../modules/aws/node_group"
  name                          = "${var.stackname}-mapit-1"
  vpc_id                        = "${data.terraform_remote_state.infra_vpc.vpc_id}"
  default_tags                  = "${map("Project", var.stackname, "aws_stackname", var.stackname, "aws_environment", var.aws_environment, "aws_migration", "mapit", "aws_hostname", "mapit-1")}"
  instance_subnet_ids           = "${matchkeys(values(data.terraform_remote_state.infra_networking.private_subnet_names_ids_map), keys(data.terraform_remote_state.infra_networking.private_subnet_names_ids_map), list(var.mapit_1_subnet))}"
  instance_security_group_ids   = ["${data.terraform_remote_state.infra_security_groups.sg_mapit_id}", "${data.terraform_remote_state.infra_security_groups.sg_management_id}"]
  instance_type                 = "${var.instance_type}"
  instance_additional_user_data = "${join("\n", null_resource.user_data.*.triggers.snippet)}"
  instance_elb_ids_length       = "1"
  instance_elb_ids              = ["${aws_elb.mapit_elb.id}"]
  instance_ami_filter_name      = "${var.instance_ami_filter_name}"
  asg_notification_topic_arn    = "${data.terraform_remote_state.infra_monitoring.sns_topic_autoscaling_group_events_arn}"
  root_block_device_volume_size = "20"
}

resource "aws_ebs_volume" "mapit-1" {
  availability_zone = "${lookup(data.terraform_remote_state.infra_networking.private_subnet_names_azs_map, var.mapit_1_subnet)}"
  size              = 20
  type              = "gp2"

  tags {
    Name            = "${var.stackname}-mapit"
    Project         = "${var.stackname}"
    Device          = "xvdf"
    aws_hostname    = "mapit-1"
    aws_migration   = "mapit"
    aws_stackname   = "${var.stackname}"
    aws_environment = "${var.aws_environment}"
  }
}

module "mapit-2" {
  source                        = "../../modules/aws/node_group"
  name                          = "${var.stackname}-mapit-2"
  vpc_id                        = "${data.terraform_remote_state.infra_vpc.vpc_id}"
  default_tags                  = "${map("Project", var.stackname, "aws_stackname", var.stackname, "aws_environment", var.aws_environment, "aws_migration", "mapit", "aws_hostname", "mapit-2")}"
  instance_subnet_ids           = "${matchkeys(values(data.terraform_remote_state.infra_networking.private_subnet_names_ids_map), keys(data.terraform_remote_state.infra_networking.private_subnet_names_ids_map), list(var.mapit_2_subnet))}"
  instance_security_group_ids   = ["${data.terraform_remote_state.infra_security_groups.sg_mapit_id}", "${data.terraform_remote_state.infra_security_groups.sg_management_id}"]
  instance_type                 = "${var.instance_type}"
  instance_additional_user_data = "${join("\n", null_resource.user_data.*.triggers.snippet)}"
  instance_elb_ids_length       = "1"
  instance_elb_ids              = ["${aws_elb.mapit_elb.id}"]
  instance_ami_filter_name      = "${var.instance_ami_filter_name}"
  asg_notification_topic_arn    = "${data.terraform_remote_state.infra_monitoring.sns_topic_autoscaling_group_events_arn}"
  root_block_device_volume_size = "20"
}

resource "aws_ebs_volume" "mapit-2" {
  availability_zone = "${lookup(data.terraform_remote_state.infra_networking.private_subnet_names_azs_map, var.mapit_2_subnet)}"
  size              = 20
  type              = "gp2"

  tags {
    Name            = "${var.stackname}-mapit"
    Project         = "${var.stackname}"
    Device          = "xvdf"
    aws_hostname    = "mapit-2"
    aws_migration   = "mapit"
    aws_stackname   = "${var.stackname}"
    aws_environment = "${var.aws_environment}"
  }
}

resource "aws_iam_policy" "mapit_iam_policy" {
  name   = "${var.stackname}-mapit-additional"
  path   = "/"
  policy = "${file("${path.module}/additional_policy.json")}"
}

resource "aws_iam_role_policy_attachment" "mapit_1_iam_role_policy_attachment" {
  role       = "${module.mapit-1.instance_iam_role_name}"
  policy_arn = "${aws_iam_policy.mapit_iam_policy.arn}"
}

resource "aws_iam_role_policy_attachment" "mapit_2_iam_role_policy_attachment" {
  role       = "${module.mapit-2.instance_iam_role_name}"
  policy_arn = "${aws_iam_policy.mapit_iam_policy.arn}"
}

module "alarms-elb-mapit-internal" {
  source                         = "../../modules/aws/alarms/elb"
  name_prefix                    = "${var.stackname}-mapit-internal"
  alarm_actions                  = ["${data.terraform_remote_state.infra_monitoring.sns_topic_cloudwatch_alarms_arn}"]
  elb_name                       = "${aws_elb.mapit_elb.name}"
  httpcode_backend_4xx_threshold = "0"
  httpcode_backend_5xx_threshold = "100"
  httpcode_elb_4xx_threshold     = "0"
  httpcode_elb_5xx_threshold     = "100"
  surgequeuelength_threshold     = "0"
  healthyhostcount_threshold     = "0"
}

# Outputs
# --------------------------------------------------------------

output "mapit_service_dns_name" {
  value       = "${aws_route53_record.mapit_service_record.fqdn}"
  description = "DNS name to access the mapit internal service"
}

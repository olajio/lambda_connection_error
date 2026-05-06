variable "region" {
  description = "Region"
  default     = "us-east-2"
}

variable "region_virginia" {
  description = "Region"
  default     = "us-east-1"
}

variable "account_id" {
  description = "Account ID"
  default     = ""
}

variable "instance_type" {
  description = "Instance type to be used in ASG."
  default = "m5.large"
}

variable "component" {
  description = "Module name or abbreviation"
  default     = ""
}

variable "naming_prefix" {
  description = "The prefix that will be used for all resources created. Default to project-environment-region-module-"
  default     = ""
}

variable "naming_prefix_virginia" {
  description = "The prefix that will be used for all resources created. Default to project-environment-region-module-"
  default     = ""
}


variable "cb_role_name" {
  description = "The role name under which runs Prometheus Code Build. Must be granted kms grant permissions."
  default     = "InfrastructureCodeBuildCustomServiceRole"
}

variable "more_tags" {
  description = "Apply more tags to the solution"
  type        = map(string)
  default     = {}
}

variable "org_id" {
  description = "Organization id. Default is to take it with tf data."
  type        = string
  default     = ""
}

variable "sns_kms_master_key_id" {
  description = "SNS topic kms key."
  type        = string
  default     = "alias/aws/sns"
}
# Copyright (c) 2023 Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl.

variable "tenancy_ocid" {}
variable "region" {description = "Your tenancy home region"}
variable "user_ocid" {default = ""}
variable "fingerprint" {default = ""}
variable "private_key_path" {default = ""}
variable "private_key_password" {default = ""}


#-------------------------------------------------------------
#-- Arbitrary compartments topology
#-------------------------------------------------------------
variable "compartments_configuration" {
  description = "The compartments configuration. Use the compartments attribute to define your topology. OCI supports compartment hierarchies up to six levels."
  type = object({
    default_parent_id = string 
    default_defined_tags = optional(map(string)) 
    default_freeform_tags = optional(map(string)) 
    enable_delete = optional(bool) 
    compartments = map(object({
      name          = string
      description   = string
      parent_id   = optional(string)
      defined_tags  = optional(map(string))
      freeform_tags = optional(map(string))
      tag_defaults     = optional(map(object({
        tag_id = string,
        default_value = string,
        is_user_required = optional(bool)
      })))
      children      = optional(map(object({
        name          = string
        description   = string
        defined_tags  = optional(map(string))
        freeform_tags = optional(map(string))
        tag_defaults     = optional(map(object({
            tag_id = string,
            default_value = string,
            is_user_required = optional(bool)
          })))
        children      = optional(map(object({
          name          = string
          description   = string
          defined_tags  = optional(map(string))
          freeform_tags = optional(map(string))
          tag_defaults     = optional(map(object({
            tag_id = string,
            default_value = string,
            is_user_required = optional(bool)
          })))
          children      = optional(map(object({
            name          = string
            description   = string
            defined_tags  = optional(map(string))
            freeform_tags = optional(map(string))
            tag_defaults     = optional(map(object({
              tag_id = string,
              default_value = string,
              is_user_required = optional(bool)
            })))
            children      = optional(map(object({
              name          = string
              description   = string
              defined_tags  = optional(map(string))
              freeform_tags = optional(map(string))
              tag_defaults     = optional(map(object({
                tag_id = string,
                default_value = string,
                is_user_required = optional(bool)
              })))
              children      = optional(map(object({
                name          = string
                description   = string
                defined_tags  = optional(map(string))
                freeform_tags = optional(map(string))
                tag_defaults     = optional(map(object({
                  tag_id = string,
                  default_value = string,
                  is_user_required = optional(bool)
                })))
              })))  
            })))
          })))
        })))
      })))  
    }))
  })
}
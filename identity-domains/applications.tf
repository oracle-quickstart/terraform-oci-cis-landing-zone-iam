# Copyright (c) 2023 Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl.
data "oci_identity_domain" "apps_domain" {
  for_each = (var.identity_domain_applications_configuration != null ) ? (var.identity_domain_applications_configuration["applications"] != null ? var.identity_domain_applications_configuration["applications"] : {}) : {}
    domain_id = each.value.identity_domain_id != null ? each.value.identity_domain_id : var.identity_domain_applications_configuration.default_identity_domain_id
}

data "oci_identity_domain" "service_provider_domain" {
  for_each = local.target_sps
    domain_id = each.value
}

data "http" "sp_signing_cert" {
  for_each = local.target_sps
     # url = join("",[data.oci_identity_domain.service_provider_domain[each.key].url,local.sign_cert_uri])
     url = join("",contains(keys(oci_identity_domain.these),coalesce(each.value,"None")) ? [oci_identity_domain.these[each.value].url] : [data.oci_identity_domain.service_provider_domain[each.key].url],[local.sign_cert_uri])
  depends_on = [
      oci_identity_domains_setting.cert_public_access_setting
  ]
}

data "oci_identity_domains_app_roles" "client_app_roles" {
    for_each  =  tomap({
      for role in local.app_roles : role.role_name => role
  })
      idcs_endpoint = contains(keys(oci_identity_domain.these),coalesce(each.value.app.identity_domain_id,"None")) ? oci_identity_domain.these[each.value.app.identity_domain_id].url : (contains(keys(oci_identity_domain.these),coalesce(var.identity_domain_applications_configuration.default_identity_domain_id,"None") ) ? oci_identity_domain.these[var.identity_domain_applications_configuration.default_identity_domain_id].url : data.oci_identity_domain.apps_domain[each.value.app_key].url)

      app_role_filter = "displayname eq \"${each.value.role_name}\" and app.value eq \"IDCSAppId\""  
      #app_role_filter  = join(" or ",[for role in each.value.application_roles : "displayname eq ${role} and app.value eq \"IDCSAppId\""])
}

data "oci_identity_domains_group" "granted_app_group" {
  for_each = tomap({
    for group in local.app_groups : group.app_key => group
  })
    idcs_endpoint = contains(keys(oci_identity_domain.these),coalesce(each.value.app.identity_domain_id,"None")) ? oci_identity_domain.these[each.value.app.identity_domain_id].url : (contains(keys(oci_identity_domain.these),coalesce(var.identity_domain_applications_configuration.default_identity_domain_id,"None") ) ? oci_identity_domain.these[var.identity_domain_applications_configuration.default_identity_domain_id].url : data.oci_identity_domain.apps_domain[each.value.app_key].url)
    group_id = each.value.group_id
}

locals {
  grant_types               = ["authorization_code", "client_credentials", "resource_owner", "refresh_token", "implicit", "tls_client_auth", "jwt_assertion", "saml2_assertion", "device_code"]
  application_types         = ["SAML", "Mobile", "Confidential", "Enterprise","SCIM"]
  allowed_operations        = ["introspect","onBehalfOfUser"]
  encryption_algorithms     = ["A128CBC-HS256","A192CBC-HS384","A256CBC-HS512","A128GCM","A192GCM","A256GCM"]
  assertion_encryption_algorithms = ["AES-128","AES-192","AES-256","AES-128-CGM","AES-256-GCM","3DES"]
  assertion_key_encryption_algorithms = ["RSA-V1.5", "RSA-OAEP"]
  authorized_resources      = ["All","Specific"]
  application_roles         = ["Me","Cloud Gate","Kerberos Administrator","DB Administrator","MFA Client","Authenticator Client","Posix Viewer","Me Password Validator","Identity Domain Administrator","Security Administrator","User Administrator","User Manager","Help Desk Administrator","Application Administrator","Audit Administrator","Change Password","Reset Password","Self Registration","Forgot Password","Verify Email"]
  app_roles                 = flatten([
      for app_key,app in var.identity_domain_applications_configuration != null ? var.identity_domain_applications_configuration.applications : {} :[
          for role_key,role in app.application_roles != null ? app.application_roles : [] : {
            app_key   = app_key
            app       = app
            role_key  = role_key
            role_name = role
          }
      ]])
  app_groups                 = flatten([
      for app_key,app in var.identity_domain_applications_configuration != null ? var.identity_domain_applications_configuration.applications : {} : [
          for grp_key,group in app.application_group_ids != null ? app.application_group_ids : [] : {
            app_key   = app_key
            app       = app
            group_key = grp_key
            #group_id = (length(regexall("^ocid1.*$", group)) > 0 ?  var.compartments_dependency[group].id) : oci_identity_domains_group.these[group].id
            group_id  = group
          }
      ]])
  sign_cert_uri             = "/admin/v1/SigningCert/jwk"
  authn_server_op           =  { for k,v in var.identity_domain_applications_configuration != null ? var.identity_domain_applications_configuration.applications : {} :  k => 
                  "{\"op\": \"${v.authentication_server_url == null ? "remove" : "replace"}\",\"path\": \"urn:ietf:params:scim:schemas:oracle:idcs:extension:managedapp:App:bundleConfigurationProperties[name eq \\\"authenticationServerUrl\\\"].value\",\"value\": [\"${v.authentication_server_url == null ? "nothing" : v.authentication_server_url}\"]}"
                 if v.type == "SCIM"
                 }
  provisioning_op           =  { for k,v in var.identity_domain_applications_configuration != null ? var.identity_domain_applications_configuration.applications : {} :  k => 
                  "{\"op\": \"replace\",\"path\": \"urn:ietf:params:scim:schemas:oracle:idcs:extension:managedapp:App:bundleConfigurationProperties[name eq \\\"clientid\\\"].value\",\"value\": [\"${v.target_app_id != null ? oci_identity_domains_app.these[v.target_app_id].name : v.client_id}\"]},{\"op\": \"replace\",\"path\": \"urn:ietf:params:scim:schemas:oracle:idcs:extension:managedapp:App:bundleConfigurationProperties[name eq \\\"clientSecret\\\"].value\",\"value\": [\"${v.target_app_id != null ? oci_identity_domains_app.these[v.target_app_id].client_secret : v.client_secret}\"]},{\"op\": \"replace\",\"path\": \"urn:ietf:params:scim:schemas:oracle:idcs:extension:managedapp:App:bundleConfigurationProperties[name eq \\\"host\\\"].value\",\"value\": [\"${v.target_app_id != null ? trimsuffix(trimprefix(oci_identity_domains_app.these[v.target_app_id].idcs_endpoint,"https://"),":443") : v.host_name}\"]}"
                 if v.type == "SCIM"
                 }
  target_sps                =  { for k,v in var.identity_domain_applications_configuration != null ? var.identity_domain_applications_configuration.applications : {} :  k => v.identity_domain_sp_id
                 if v.identity_domain_sp_id != null
                 }
  # saml_attributemapping_op           =  { for k,v in var.identity_domain_applications_configuration != null ? var.identity_domain_applications_configuration.applications : {} :  k => 
  #                 "{\"op\": \"replace\",\"path\": \"attributeMappings\",\"value\": [{\"managedObjectAttributeName\":\"ATTR1\",\"samlFormat\":\"Basic\",\"idcsAttributeName\":\"username\"},{\"managedObjectAttributeName\":\"ATTR2\",\"samlFormat\":\"Basic\",\"idcsAttributeName\":\"name.givenName\"},]}]}"
  #                if v.type == "SAML" && v.attribute_configuration != null
  #                }
  saml_attributemapping_op  =  { for k,v in var.identity_domain_applications_configuration != null ? var.identity_domain_applications_configuration.applications : {} :  k => join("",[for attrs in v.attribute_configuration : "{\"managedObjectAttributeName\": \"${attrs.assertion_attribute}\",\"samlFormat\": \"${attrs.format}\",\"idcsAttributeName\": \"${attrs.identity_domain_attribute}\"},"])
                
                 if v.type == "SAML" && v.attribute_configuration != null
                 }
  
  
      
}

resource "oci_identity_domains_oauth_client_certificate" "app_client_cert" {
  for_each       = var.identity_domain_applications_configuration != null ? {for k,v in var.identity_domain_applications_configuration.applications : k => v if v.app_client_certificate != null} : {}
    #Required
    certificate_alias = each.value.app_client_certificate.alias
    idcs_endpoint = contains(keys(oci_identity_domain.these),coalesce(each.value.identity_domain_id,"None")) ? oci_identity_domain.these[each.value.identity_domain_id].url : (contains(keys(oci_identity_domain.these),coalesce(var.identity_domain_applications_configuration.default_identity_domain_id,"None") ) ? oci_identity_domain.these[var.identity_domain_applications_configuration.default_identity_domain_id].url : data.oci_identity_domain.apps_domain[each.key].url)
    schemas = ["urn:ietf:params:scim:schemas:oracle:idcs:OAuthClientCertificate"]
    x509base64certificate = each.value.app_client_certificate.base64certificate
}

resource "oci_identity_domains_grant" "app_roles_grant" {
  #for_each       = var.identity_domain_applications_configuration != null ? var.identity_domain_applications_configuration.applications : {}
  for_each  =  tomap({
      for role in local.app_roles : "${role.app_key}.${role.role_key}" => role
  })

    grant_mechanism = "ADMINISTRATOR_TO_APP"
    grantee {
          type = "App"
          value = oci_identity_domains_app.these[each.value.app_key].id
    }
    idcs_endpoint = contains(keys(oci_identity_domain.these),coalesce(each.value.app.identity_domain_id,"None")) ? oci_identity_domain.these[each.value.app.identity_domain_id].url : (contains(keys(oci_identity_domain.these),coalesce(var.identity_domain_applications_configuration.default_identity_domain_id,"None") ) ? oci_identity_domain.these[var.identity_domain_applications_configuration.default_identity_domain_id].url : data.oci_identity_domain.apps_domain[each.value.app_key].url)
    schemas = ["urn:ietf:params:scim:schemas:oracle:idcs:Grant"]
    app {
        value = "IDCSAppId"
    }
    entitlement {
      attribute_name = "appRoles"
      #attribute_value = data.oci_identity_domains_app_roles.client_app_roles[each.value.app_key].app_roles.0.id
      attribute_value = data.oci_identity_domains_app_roles.client_app_roles[each.value.role_name].app_roles.0.id
        
    }
}

resource "oci_identity_domains_grant" "app_groups_grant" {
  for_each  =  tomap({
      for group in local.app_groups : "${group.app_key}.${group.group_key}" => group
  })

    grant_mechanism = "ADMINISTRATOR_TO_GROUP"
    grantee {
          type = "Group"
          value = length(regexall("^ocid1.*$", each.value.group_id)) > 0 ? data.oci_identity_domains_group.granted_app_group[each.value.group_id].id : oci_identity_domains_group.these[each.value.group_id].id
    }
    idcs_endpoint = contains(keys(oci_identity_domain.these),coalesce(each.value.app.identity_domain_id,"None")) ? oci_identity_domain.these[each.value.app.identity_domain_id].url : (contains(keys(oci_identity_domain.these),coalesce(var.identity_domain_applications_configuration.default_identity_domain_id,"None") ) ? oci_identity_domain.these[var.identity_domain_applications_configuration.default_identity_domain_id].url : data.oci_identity_domain.apps_domain[each.value.app_key].url)
    schemas = ["urn:ietf:params:scim:schemas:oracle:idcs:Grant"]
    app {
        value = oci_identity_domains_app.these[each.value.app_key].id
    }

}

resource "oci_identity_domains_setting" "cert_public_access_setting" {
  for_each       = {
    for k,v in var.identity_domains_configuration != null ? var.identity_domains_configuration.identity_domains : {} : k => v
    if v.allow_signing_cert_public_access 
  }
    #Required
    csr_access      = "none"
    idcs_endpoint   = oci_identity_domain.these[each.key].url
    schemas         = ["urn:ietf:params:scim:schemas:oracle:idcs:Settings"]
    setting_id      = "Settings"
    signing_cert_public_access = true
}

resource "oci_identity_domains_app" "these" {
  for_each       = var.identity_domain_applications_configuration != null ? var.identity_domain_applications_configuration.applications : {}
    lifecycle {
      ## Check 1: Valid grant types.
      precondition {
        condition = each.value.allowed_grant_types != null ? length(setsubtract(each.value.allowed_grant_types,local.grant_types)) == 0 : true
        error_message = "VALIDATION FAILURE in application \"${each.key}\": invalid value for \"allowed_grant_types\" attribute. Valid values are ${join(",",local.grant_types)}."
      }
      ## Check 2: Verify not null for redirect url.
      precondition {
        condition = each.value.redirect_urls == null && !contains(["SAML","SCIM"],each.value.type) ? !(contains(local.grant_types, "implicit")||contains(local.grant_types, "authorization_code"))  : true
        error_message = "VALIDATION FAILURE in application \"${each.key}\": invalid value for \"redirect_urls\" attribute. A valid value must be provided if \"allowed_grant_types\" is \"implicit\" or \"authorization_code\""
      }
      # Check 3: Verify application type value.
      precondition {
        condition = each.value.type != null ? contains(local.application_types, each.value.type)  : true
        error_message = "VALIDATION FAILURE in application \"${each.key}\": invalid value for \"type\" attribute. Valid values are ${join(",",local.application_types)}."
      }
      # Check 4: Verify certificate alias is provided when using Trusted client type.
      precondition {
        condition = each.value.client_type != null ? !(each.value.client_type == "trusted" && each.value.app_client_certificate == null) || each.value.client_type != "trusted" : true
        error_message = "VALIDATION FAILURE in application \"${each.key}\": invalid value for \"app_client_certificate\" attribute. Provide a signing certificate when Client Type is trusted"
      }
      # Check 5: Verify id token encryption algorithm value.
      precondition {
        condition = each.value.id_token_encryption_algorithm != null ? contains(local.encryption_algorithms,each.value.id_token_encryption_algorithm) : true
        error_message = "VALIDATION FAILURE in application \"${each.key}\": invalid value for \"id_token_encryption_algorithm\" attribute. Valid values are ${join(",",local.encryption_algorithms)}."
      }
      # Check 8: Verify primary audience is provided for a Resource Server app.
      precondition {
        condition = coalesce(each.value.configure_as_oauth_resource_server,false) ? each.value.primary_audience != null : true
        error_message = "VALIDATION FAILURE in application \"${each.key}\": invalid value for \"primary_audience\" attribute. Provide a Primary Audience when configuring OAuth Resource Server."
      }
      # Check 7: Verfiy valid Application Roles.
      precondition {
        condition = each.value.application_roles !=null ? contains([for role in each.value.application_roles: (contains(local.application_roles,role) ? true : false)],false)? false : true : true
        error_message = "VALIDATION FAILURE in application \"${each.key}\": invalid value for \"application_roles\" attribute. Valid values are ${join(",",local.application_roles)}."
      }
      # Check 8: Verfiy if admin consent has been granted.
      precondition {
        condition = each.value.admin_consent_granted ==null && each.value.type == "SCIM" && each.value.enable_provisioning == true ? false : true
        error_message = "VALIDATION FAILURE in application \"${each.key}\": Admin consent has not been granted for provisioning. Grant it by setting \"admin_consent_granted\" after reading ."
      }
      # Check 9: Verify assertion encryption algorithm value.
      precondition {
        condition = each.value.encryption_algorithm != null ? contains(local.assertion_encryption_algorithms,each.value.encryption_algorithm) : true
        error_message = "VALIDATION FAILURE in application \"${each.key}\": invalid value for \"encryption_algorithm\" attribute. Valid values are ${join(",",local.assertion_encryption_algorithms)}."
      }
      # Check 10: Verify assertion key encryption algorithm value.
      precondition {
        condition = each.value.key_encryption_algorithm != null ? contains(local.assertion_key_encryption_algorithms,each.value.key_encryption_algorithm) : true
        error_message = "VALIDATION FAILURE in application \"${each.key}\": invalid value for \"key_encryption_algorithm\" attribute. Valid values are ${join(",",local.assertion_key_encryption_algorithms)}."
      }

    } 
    idcs_endpoint             = contains(keys(oci_identity_domain.these),coalesce(each.value.identity_domain_id,"None")) ? oci_identity_domain.these[each.value.identity_domain_id].url : (contains(keys(oci_identity_domain.these),coalesce(var.identity_domain_applications_configuration.default_identity_domain_id,"None") ) ? oci_identity_domain.these[var.identity_domain_applications_configuration.default_identity_domain_id].url : data.oci_identity_domain.apps_domain[each.key].url)
    display_name              = each.value.display_name
    description               = each.value.description
    schemas                   = [
                                 "urn:ietf:params:scim:schemas:oracle:idcs:App",
                                 "urn:ietf:params:scim:schemas:oracle:idcs:extension:OCITags",
                                 "urn:ietf:params:scim:schemas:oracle:idcs:extension:managedapp:App"
                                ] #["urn:ietf:params:scim:schemas:oracle:idcs:App","urn:ietf:params:scim:schemas:oracle:idcs:extension:managedapp:App"]  #["urn:ietf:params:scim:schemas:oracle:idcs:App","urn:ietf:params:scim:schemas:oracle:idcs:extension:managedapp:app:bundleConfigurationProperties"]
   
    based_on_template {
            value = each.value.type == "Confidential" ? "CustomWebAppTemplateId" : (each.value.type == "SAML" ? "CustomSAMLAppTemplateId" : (each.value.type == "Enterprise" ? "CustomEnterpriseAppTemplateId" : (each.value.type == "Mobile" ? "CustomBrowserMobileTemplateId" : (each.value.type == "SCIM" ? "170c671e7cc13a78a480a2d1f8a5d123" : null)))) # "170c671e7cc13a78a480a2d1f8a5d123" : null))))
    }
    # URLS and General Configuration
    landing_page_url          = each.value.app_url
    login_page_url            = each.value.custom_signin_url
    logout_page_url           = each.value.custom_signout_url
    error_page_url            = each.value.custom_error_url
    linking_callback_url      = each.value.custom_social_linking_callback_url

    active                    = coalesce(each.value.active,false)
    # Display Settings
    show_in_my_apps           = each.value.display_in_my_apps
    #   user_can_request_access???????

    # Authentication and Authorization
    allow_access_control      = each.value.enforce_grants_as_authorization
    
    #OAUTH Configuration
    is_oauth_client           = coalesce(each.value.configure_as_oauth_client,false)
    allowed_grants            = [for grant in each.value.allowed_grant_types != null ? each.value.allowed_grant_types : [] : grant=="jwt_assertion" ? "urn:ietf:params:oauth:grant-type:jwt-bearer" :(grant == "saml2_assertion" ? "urn:ietf:params:oauth:grant-type:saml2-bearer":(grant == "resource_owner") ? "password": (grant == "device_code" ? "urn:ietf:params:oauth:grant-type:device_code" : grant))]
    all_url_schemes_allowed   = each.value.allow_non_https_urls
    redirect_uris             = each.value.redirect_urls
    post_logout_redirect_uris = each.value.post_logout_redirect_urls
    logout_uri                = each.value.logout_url
    client_type               = each.value.client_type
    allowed_operations        = compact(concat([coalesce(each.value.allow_introspect_operation,false) ? "introspect" : ""],[coalesce(each.value.allow_on_behalf_of_operation,false) ? "onBehalfOfUser" : ""]))
    dynamic "certificates" {
      for_each = each.value.app_client_certificate != null ? [each.value.app_client_certificate["alias"]] : []
      content {
        cert_alias = oci_identity_domains_oauth_client_certificate.app_client_cert[each.key].certificate_alias
      }        
    }
    id_token_enc_algo         = each.value.id_token_encryption_algorithm
    bypass_consent            = coalesce(each.value.bypass_consent,false)
    trust_scope               = each.value.authorized_resources != null ? (each.value.authorized_resources=="All" ? "Account" : "Explicit") : "Explicit"
    dynamic allowed_scopes {
      for_each = each.value.resources != null ? each.value.resources : []
      content {
          fqs                 = allowed_scopes.value
        }
    }
    #Resource Server Configuration
    is_oauth_resource         = coalesce(each.value.configure_as_oauth_resource_server,false)
    access_token_expiry       = coalesce(each.value.access_token_expiration, 3600)
    refresh_token_expiry      = coalesce(each.value.allow_token_refresh,false) ? coalesce(each.value.refresh_token_expiration, 604800) : null
    audience                  = each.value.primary_audience
    secondary_audiences       = each.value.secondary_audiences
    dynamic scopes {
      for_each = each.value.scopes != null ? each.value.scopes : {}
      content {
          value               = scopes.value
          display_name        = scopes.display_name
          description         = scopes.description
          requires_consent    = coalesce(scopes.requires_user_consent,false)
      }
    }
    # SAML SSO Configuration

    dynamic urnietfparamsscimschemasoracleidcsextensionsaml_service_provider_app {
        for_each = each.value.type == "SAML" ? ["yes"] : []
        ### App Links TBA - This needs a new apps resource to create the alias apps and then referred to them with alias_apps parameter.  Normally alias apps are created using /admin/v1/Bulk.
      content {     
        partner_provider_id         = each.value.identity_domain_sp_id == null ? each.value.entity_id : contains(keys(oci_identity_domain.these),coalesce(each.value.identity_domain_sp_id,"None")) ? "${oci_identity_domain.these[each.value.identity_domain_sp_id].url}/fed" : "${data.oci_identity_domain.service_provider_domain[each.key].url}/fed"
        assertion_consumer_url      = each.value.identity_domain_sp_id == null ? each.value.assertion_consumer_url : contains(keys(oci_identity_domain.these),coalesce(each.value.identity_domain_sp_id,"None")) ? "${oci_identity_domain.these[each.value.identity_domain_sp_id].url}/fed/v1/sp/sso" : "${data.oci_identity_domain.service_provider_domain[each.key].url}/fed/v1/sp/sso"
        signing_certificate         = each.value.identity_domain_sp_id == null ? each.value.signing_certificate : jsondecode(data.http.sp_signing_cert[each.key].response_body).keys[0].x5c[0] 
        name_id_format              = coalesce(each.value.name_id_format,"saml-emailaddress")
        name_id_userstore_attribute = coalesce(each.value.name_id_value,"emails.primary.value")
        sign_response_or_assertion  = coalesce(each.value.signed_sso,"Assertion")
        logout_enabled              = coalesce(each.value.enable_single_logout,false)
        logout_binding              = coalesce(each.value.logout_binding,"Redirect")
        logout_request_url          = each.value.identity_domain_sp_id == null ? each.value.single_logout_url : contains(keys(oci_identity_domain.these),coalesce(each.value.identity_domain_sp_id,"None")) ? "${oci_identity_domain.these[each.value.identity_domain_sp_id].url}/fed/v1/sp/slo" : "${data.oci_identity_domain.service_provider_domain[each.key].url}/fed/v1/sp/slo"
        logout_response_url         = each.value.identity_domain_sp_id == null ? each.value.logout_response_url : contains(keys(oci_identity_domain.these),coalesce(each.value.identity_domain_sp_id,"None")) ? "${oci_identity_domain.these[each.value.identity_domain_sp_id].url}/fed/v1/sp/slo" : "${data.oci_identity_domain.service_provider_domain[each.key].url}/fed/v1/sp/slo"
         ### Encrypted Assertion
        encrypt_assertion           = coalesce(each.value.require_encrypted_assertion,false)
        encryption_certificate      = each.value.encryption_certificate
        encryption_algorithm        = coalesce(each.value.encryption_algorithm,"AES-128")
        key_encryption_algorithm    = coalesce(each.value.key_encryption_algorithm,"RSA-v1.5")
         ### Atrribute Configuration TBA - Attribute mappings are patched using /admin/v1/MappedAttributes which is missing in OCI SDK, a workaround is to use a provisioner with oci raw-request to patch the resource
      }
    }
        
    

  
    is_enterprise_app = each.value.type == "Enterprise" ? true : false
    #is_mobile_target = each.value.type == "Mobile" ? true : false
    
    
    #is_oauth_resource = each.value.type == "Confidential" ? true : false

    # Identity Domain Catalog App
    dynamic urnietfparamsscimschemasoracleidcsextensionmanagedapp_app {
      for_each = each.value.type == "SCIM" ? ["yes"] : []
        content {
          connected        = each.value.enable_provisioning
          enable_sync      = each.value.enable_synchronization
          is_authoritative = each.value.authoritative_sync
          admin_consent_granted = each.value.admin_consent_granted
        }
    }

    urnietfparamsscimschemasoracleidcsextension_oci_tags {

        dynamic "defined_tags" {
            for_each = each.value.defined_tags != null ? each.value.defined_tags : (var.identity_domain_applications_configuration.default_defined_tags !=null ? var.identity_domain_applications_configuration.default_defined_tags : {})
               content {
                 key = split(".",defined_tags["key"])[1]
                 namespace = split(".",defined_tags["key"])[0]
                 value = defined_tags["value"]
               }
        }
        dynamic "freeform_tags" {
            for_each = each.value.freeform_tags != null ? each.value.freeform_tags : (var.identity_domain_applications_configuration.default_freeform_tags !=null ? var.identity_domain_applications_configuration.default_freeform_tags : {})
               content {
                 key = freeform_tags["key"]
                 value = freeform_tags["value"]
               }
        }

    }
  depends_on = [
      oci_identity_domains_setting.cert_public_access_setting
  ]
}

resource "null_resource" "app_patch" {    #Patches SCIM app with provisioning parameers
  for_each       = { for k,v  in var.identity_domain_applications_configuration != null ? var.identity_domain_applications_configuration.applications : {} : k=>v if v.type == "SCIM"}
    provisioner "local-exec" {
      #command = "oci identity-domains app patch --schemas '[\"urn:ietf:params:scim:api:messages:2.0:PatchOp\"]' --endpoint ${self.idcs_endpoint} --app-id ${self.id} --operations '[{\"op\": \"replace\",\"path\": \"urn:ietf:params:scim:schemas:oracle:idcs:extension:managedapp:App:bundleConfigurationProperties[name eq \\\"authenticationServerUrl\\\"].value\",\"value\": [\"${each.value.authentication_server_url}\"]},{\"op\": \"replace\",\"path\": \"urn:ietf:params:scim:schemas:oracle:idcs:extension:managedapp:App:bundleConfigurationProperties[name eq \\\"clientid\\\"].value\",\"value\": [\"${each.value.client_id}\"]},{\"op\": \"replace\",\"path\": \"urn:ietf:params:scim:schemas:oracle:idcs:extension:managedapp:App:bundleConfigurationProperties[name eq \\\"clientSecret\\\"].value\",\"value\": [\"${each.value.client_secret}\"]},{\"op\": \"replace\",\"path\": \"urn:ietf:params:scim:schemas:oracle:idcs:extension:managedapp:App:bundleConfigurationProperties[name eq \\\"host\\\"].value\",\"value\": [\"${each.value.host_name}\"]}]'"
      #command = "[ ${oci_identity_domains_app.these[each.key].is_managed_app} = false ] && (exit 0) || oci identity-domains app patch --schemas '[\"urn:ietf:params:scim:api:messages:2.0:PatchOp\"]' --endpoint ${oci_identity_domains_app.these[each.key].idcs_endpoint} --app-id ${oci_identity_domains_app.these[each.key].id} --operations '[{\"op\": \"replace\",\"path\": \"urn:ietf:params:scim:schemas:oracle:idcs:extension:managedapp:App:bundleConfigurationProperties[name eq \\\"authenticationServerUrl\\\"].value\",\"value\": [\"${each.value.authentication_server_url}\"]},{\"op\": \"replace\",\"path\": \"urn:ietf:params:scim:schemas:oracle:idcs:extension:managedapp:App:bundleConfigurationProperties[name eq \\\"clientid\\\"].value\",\"value\": [\"${oci_identity_domains_app.these[each.value.target_app_id].name}\"]},{\"op\": \"replace\",\"path\": \"urn:ietf:params:scim:schemas:oracle:idcs:extension:managedapp:App:bundleConfigurationProperties[name eq \\\"clientSecret\\\"].value\",\"value\": [\"${oci_identity_domains_app.these[each.value.target_app_id].client_secret}\"]},{\"op\": \"replace\",\"path\": \"urn:ietf:params:scim:schemas:oracle:idcs:extension:managedapp:App:bundleConfigurationProperties[name eq \\\"host\\\"].value\",\"value\": [\"${oci_identity_domains_app.these[each.value.target_app_id].idcs_endpoint}\"]}]'"
      #command = "[ ${self.is_managed_app} = false ] && (exit 0) || oci identity-domains app patch --schemas '[\"urn:ietf:params:scim:api:messages:2.0:PatchOp\"]' --endpoint ${self.idcs_endpoint} --app-id ${self.id} --operations '[{\"op\": \"replace\",\"path\": \"urn:ietf:params:scim:schemas:oracle:idcs:extension:managedapp:App:bundleConfigurationProperties[name eq \\\"authenticationServerUrl\\\"].value\",\"value\": [\"${coalesce(each.value.authentication_server_url," ")}\"]},{\"op\": \"replace\",\"path\": \"urn:ietf:params:scim:schemas:oracle:idcs:extension:managedapp:App:bundleConfigurationProperties[name eq \\\"clientid\\\"].value\",\"value\": [\"${oci_identity_domains_app.these[local.target_apps[each.key]].name}\"]},{\"op\": \"replace\",\"path\": \"urn:ietf:params:scim:schemas:oracle:idcs:extension:managedapp:App:bundleConfigurationProperties[name eq \\\"clientSecret\\\"].value\",\"value\": [\"${coalesce(each.value.client_secret," ")}\"]},{\"op\": \"replace\",\"path\": \"urn:ietf:params:scim:schemas:oracle:idcs:extension:managedapp:App:bundleConfigurationProperties[name eq \\\"host\\\"].value\",\"value\": [\"${coalesce(each.value.host_name," ")}\"]}]'"
      command = "[ ${oci_identity_domains_app.these[each.key].is_managed_app} = false ] && (exit 0) || oci identity-domains app patch --schemas '[\"urn:ietf:params:scim:api:messages:2.0:PatchOp\"]' --endpoint ${oci_identity_domains_app.these[each.key].idcs_endpoint} --app-id ${oci_identity_domains_app.these[each.key].id} --operations '[${tostring(local.authn_server_op[each.key])},${tostring(local.provisioning_op[each.key])}]'"

      on_failure = fail
    }
}

resource "null_resource" "MappedAttributes_patch" {    #Patches MappedAttributes for SSO Attribute Configuration
  for_each       = { for k,v  in var.identity_domain_applications_configuration != null ? var.identity_domain_applications_configuration.applications : {} : k=>v if v.type == "SAML" && v.attribute_configuration!=null}
    provisioner "local-exec" {
      #command = "[ ${try(each.value.attribute_configuration==null?false:true,true)} = false ] && (exit 0) || oci raw-request --target-uri  ${oci_identity_domains_app.these[each.key].idcs_endpoint}/admin/v1/MappedAttributes/${oci_identity_domains_app.these[each.key].urnietfparamsscimschemasoracleidcsextensionsaml_service_provider_app[0].outbound_assertion_attributes[0].value} --http-method PATCH --request-body file://mappedattrs.json "
      command = "[ ${try(each.value.attribute_configuration==null?false:true,true)} = false ] && (exit 0) || oci raw-request --target-uri  ${oci_identity_domains_app.these[each.key].idcs_endpoint}/admin/v1/MappedAttributes/${oci_identity_domains_app.these[each.key].urnietfparamsscimschemasoracleidcsextensionsaml_service_provider_app[0].outbound_assertion_attributes[0].value} --http-method PATCH --request-body '{\"schemas\":[\"urn:ietf:params:scim:api:messages:2.0:PatchOp\"],\"Operations\":[{\"op\": \"replace\",\"path\": \"attributeMappings\",\"value\":[${local.saml_attributemapping_op[each.key]}]}]}'"
 
      on_failure = fail
    }
}







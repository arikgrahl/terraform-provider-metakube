terraform {
  required_providers {
    metakube = {
      source = "syseleven/metakube"
    }
    openstack = {
      source = "terraform-provider-openstack/openstack"
    }
  }
}

// You can download and source "OpenStack RC File v3" for your account at https://cloud.syseleven.de and source it or configure provider manually here.
// provider "openstack" {
//  auth_url = "https://keystone.cloud.syseleven.net:5000/v3"
//
//  user_name = var.username
//
//  password = var.password
//
//  tenant_name = var.tenant
//
//  domain_name = "Default"
// }

data "openstack_images_image_v2" "image" {
  most_recent = true

  visibility = "public"
  properties = {
    os_distro  = "ubuntu"
    os_version = "20.04"
  }
}

provider "metakube" {
  host = "https://metakube.syseleven.de"
}
resource "metakube_project" "project" {
  name = var.project_name
}

data "local_file" "public_sshkey" {
  filename = pathexpand(var.public_sshkey_file)
}

resource "metakube_sshkey" "local" {
  project_id = metakube_project.project.id

  name       = "local SSH key"
  public_key = data.local_file.public_sshkey.content
}

data "metakube_k8s_version" "cluster" {
  major = "1"
  minor = var.k8s_minor_version
}

resource "metakube_cluster" "cluster" {
  name       = var.cluster_name
  dc_name    = var.dc_name
  project_id = metakube_project.project.id
  sshkeys    = [metakube_sshkey.local.id]

  spec {
    enable_ssh_agent = true
    version          = data.metakube_k8s_version.cluster.version
    cloud {
      openstack {
        floating_ip_pool = var.floating_ip_pool
        password         = var.password
        tenant           = var.tenant
        username         = var.username
      }
    }
  }
}

# create admin.conf file
resource "local_file" "kubeconfig" {
  content  = metakube_cluster.cluster.kube_config
  filename = "${path.module}/admin.conf"
}

resource "metakube_node_deployment" "node_deployment" {
  name       = null // auto generate
  cluster_id = metakube_cluster.cluster.id
  spec {
    replicas = var.node_replicas
    template {
      cloud {
        openstack {
          flavor                       = var.node_flavor
          image                        = var.node_image != null ? var.node_image : data.openstack_images_image_v2.image.name
          use_floating_ip              = var.use_floating_ip
          instance_ready_check_period  = "5s"
          instance_ready_check_timeout = "100s"
        }
      }
      operating_system {
        ubuntu {
        }
      }
      versions {
        kubelet = data.metakube_k8s_version.cluster.version
      }
    }
  }

}

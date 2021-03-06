#!/bin/bash

# Copyright 2014 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# TODO(jbeda): Provide a way to override project
# gcloud multiplexing for shared GCE/GKE tests.
KUBE_ROOT=$(dirname "${BASH_SOURCE}")/../..
source "${KUBE_ROOT}/cluster/gce/config-common.sh"

GCLOUD=gcloud
ZONE=${KUBE_GCE_ZONE:-us-central1-b}
REGION=${ZONE%-*}
RELEASE_REGION_FALLBACK=${RELEASE_REGION_FALLBACK:-false}
REGIONAL_KUBE_ADDONS=${REGIONAL_KUBE_ADDONS:-true}
NODE_SIZE=${NODE_SIZE:-n1-standard-2}
NUM_NODES=${NUM_NODES:-3}
MASTER_SIZE=${MASTER_SIZE:-n1-standard-$(get-master-size)}
MASTER_DISK_TYPE=pd-ssd
MASTER_DISK_SIZE=${MASTER_DISK_SIZE:-20GB}
NODE_DISK_TYPE=${NODE_DISK_TYPE:-pd-standard}
NODE_DISK_SIZE=${NODE_DISK_SIZE:-100GB}
NODE_LOCAL_SSDS=${NODE_LOCAL_SSDS:-0}
# Accelerators to be attached to each node. Format "type=<accelerator-type>,count=<accelerator-count>"
# More information on available GPUs here - https://cloud.google.com/compute/docs/gpus/
NODE_ACCELERATORS=${NODE_ACCELERATORS:-""}
REGISTER_MASTER_KUBELET=${REGISTER_MASTER:-true}
PREEMPTIBLE_NODE=${PREEMPTIBLE_NODE:-false}
PREEMPTIBLE_MASTER=${PREEMPTIBLE_MASTER:-false}
KUBE_DELETE_NODES=${KUBE_DELETE_NODES:-true}
KUBE_DELETE_NETWORK=${KUBE_DELETE_NETWORK:-false}

MASTER_OS_DISTRIBUTION=${KUBE_MASTER_OS_DISTRIBUTION:-${KUBE_OS_DISTRIBUTION:-gci}}
NODE_OS_DISTRIBUTION=${KUBE_NODE_OS_DISTRIBUTION:-${KUBE_OS_DISTRIBUTION:-debian}}
if [[ "${MASTER_OS_DISTRIBUTION}" == "coreos" ]]; then
    MASTER_OS_DISTRIBUTION="container-linux"
fi
if [[ "${NODE_OS_DISTRIBUTION}" == "coreos" ]]; then
    NODE_OS_DISTRIBUTION="container-linux"
fi

if [[ "${MASTER_OS_DISTRIBUTION}" == "cos" ]]; then
    MASTER_OS_DISTRIBUTION="gci"
fi

if [[ "${NODE_OS_DISTRIBUTION}" == "cos" ]]; then
    NODE_OS_DISTRIBUTION="gci"
fi

# GPUs supported in GCE do not have compatible drivers in Debian 7.
if [[ "${NODE_OS_DISTRIBUTION}" == "debian" ]]; then
    NODE_ACCELERATORS=""
fi

# By default a cluster will be started with the master on GCI and nodes on
# containervm. If you are updating the containervm version, update this
# variable. Also please update corresponding image for node e2e at:
# https://github.com/kubernetes/kubernetes/blob/master/test/e2e_node/jenkins/image-config.yaml
CVM_VERSION=${CVM_VERSION:-container-vm-v20170627}
GCI_VERSION=${KUBE_GCI_VERSION:-cos-stable-59-9460-64-0}
MASTER_IMAGE=${KUBE_GCE_MASTER_IMAGE:-}
MASTER_IMAGE_PROJECT=${KUBE_GCE_MASTER_PROJECT:-cos-cloud}
NODE_IMAGE=${KUBE_GCE_NODE_IMAGE:-${CVM_VERSION}}
NODE_IMAGE_PROJECT=${KUBE_GCE_NODE_PROJECT:-cos-cloud}
CONTAINER_RUNTIME=${KUBE_CONTAINER_RUNTIME:-docker}
RKT_VERSION=${KUBE_RKT_VERSION:-1.23.0}
RKT_STAGE1_IMAGE=${KUBE_RKT_STAGE1_IMAGE:-coreos.com/rkt/stage1-coreos}

NETWORK=${KUBE_GCE_NETWORK:-default}
INSTANCE_PREFIX="${KUBE_GCE_INSTANCE_PREFIX:-kubernetes}"
CLUSTER_NAME="${CLUSTER_NAME:-${INSTANCE_PREFIX}}"
MASTER_NAME="${INSTANCE_PREFIX}-master"
AGGREGATOR_MASTER_NAME="${INSTANCE_PREFIX}-aggregator"
INITIAL_ETCD_CLUSTER="${MASTER_NAME}"
ETCD_QUORUM_READ="${ENABLE_ETCD_QUORUM_READ:-false}"
MASTER_TAG="${INSTANCE_PREFIX}-master"
NODE_TAG="${INSTANCE_PREFIX}-minion"

CLUSTER_IP_RANGE="${CLUSTER_IP_RANGE:-10.244.0.0/14}"
MASTER_IP_RANGE="${MASTER_IP_RANGE:-10.246.0.0/24}"

if [[ "${FEDERATION:-}" == true ]]; then
    NODE_SCOPES="${NODE_SCOPES:-compute-rw,monitoring,logging-write,storage-ro,https://www.googleapis.com/auth/ndev.clouddns.readwrite}"
else
    NODE_SCOPES="${NODE_SCOPES:-compute-rw,monitoring,logging-write,storage-ro}"
fi

# Extra docker options for nodes.
EXTRA_DOCKER_OPTS="${EXTRA_DOCKER_OPTS:-}"

SERVICE_CLUSTER_IP_RANGE="${SERVICE_CLUSTER_IP_RANGE:-10.0.0.0/16}"  # formerly PORTAL_NET
ALLOCATE_NODE_CIDRS=true

# When set to true, Docker Cache is enabled by default as part of the cluster bring up.
ENABLE_DOCKER_REGISTRY_CACHE=true

# Optional: Deploy a L7 loadbalancer controller to fulfill Ingress requests:
#   glbc           - CE L7 Load Balancer Controller
ENABLE_L7_LOADBALANCING="${KUBE_ENABLE_L7_LOADBALANCING:-glbc}"

# Optional: Cluster monitoring to setup as part of the cluster bring up:
#   none           - No cluster monitoring setup
#   influxdb       - Heapster, InfluxDB, and Grafana
#   google         - Heapster, Google Cloud Monitoring, and Google Cloud Logging
#   stackdriver    - Heapster, Google Cloud Monitoring (schema container), and Google Cloud Logging
#   googleinfluxdb - Enable influxdb and google (except GCM)
#   standalone     - Heapster only. Metrics available via Heapster REST API.
ENABLE_CLUSTER_MONITORING="${KUBE_ENABLE_CLUSTER_MONITORING:-influxdb}"

# One special node out of NUM_NODES would be created of this type if specified.
# Useful for scheduling heapster in large clusters with nodes of small size.
HEAPSTER_MACHINE_TYPE="${HEAPSTER_MACHINE_TYPE:-}"

# Historically fluentd was a manifest pod and then was migrated to DaemonSet.
# To avoid situation during cluster upgrade when there are two instances
# of fluentd running on a node, kubelet need to mark node on which
# fluentd is not running as a manifest pod with appropriate label.
# TODO(piosz): remove this in 1.8
NODE_LABELS="${KUBE_NODE_LABELS:-beta.kubernetes.io/fluentd-ds-ready=true}"

# To avoid running Calico on a node that is not configured appropriately, 
# label each Node so that the DaemonSet can run the Pods only on ready Nodes.
if [[ ${NETWORK_POLICY_PROVIDER:-} == "calico" ]]; then
	NODE_LABELS="${NODE_LABELS},projectcalico.org/ds-ready=true"
fi

# Turn the simple metadata proxy on by default.
ENABLE_METADATA_PROXY="${ENABLE_METADATA_PROXY:-simple}"
if [[ ${ENABLE_METADATA_PROXY} != "false" ]]; then
        NODE_LABELS="${NODE_LABELS},beta.kubernetes.io/metadata-proxy-ready=true"
fi

# Optional: Enable node logging.
ENABLE_NODE_LOGGING="${KUBE_ENABLE_NODE_LOGGING:-true}"
LOGGING_DESTINATION="${KUBE_LOGGING_DESTINATION:-gcp}" # options: elasticsearch, gcp

# Optional: When set to true, Elasticsearch and Kibana will be setup as part of the cluster bring up.
ENABLE_CLUSTER_LOGGING="${KUBE_ENABLE_CLUSTER_LOGGING:-true}"
ELASTICSEARCH_LOGGING_REPLICAS=1

# Optional: Don't require https for registries in our local RFC1918 network
if [[ ${KUBE_ENABLE_INSECURE_REGISTRY:-false} == "true" ]]; then
  EXTRA_DOCKER_OPTS="${EXTRA_DOCKER_OPTS} --insecure-registry 10.0.0.0/8"
fi

# Optional: customize runtime config
RUNTIME_CONFIG="${KUBE_RUNTIME_CONFIG:-}"

# Optional: set feature gates
FEATURE_GATES="${KUBE_FEATURE_GATES:-ExperimentalCriticalPodAnnotation=true}"

if [[ ! -z "${NODE_ACCELERATORS}" ]]; then
    FEATURE_GATES="${FEATURE_GATES},Accelerators=true"
fi

# Optional: Install cluster DNS.
ENABLE_CLUSTER_DNS="${KUBE_ENABLE_CLUSTER_DNS:-true}"
DNS_SERVER_IP="${KUBE_DNS_SERVER_IP:-10.0.0.10}"
DNS_DOMAIN="${KUBE_DNS_DOMAIN:-cluster.local}"

# Optional: Enable DNS horizontal autoscaler
ENABLE_DNS_HORIZONTAL_AUTOSCALER="${KUBE_ENABLE_DNS_HORIZONTAL_AUTOSCALER:-true}"

# Optional: Install cluster docker registry.
ENABLE_CLUSTER_REGISTRY="${KUBE_ENABLE_CLUSTER_REGISTRY:-false}"
CLUSTER_REGISTRY_DISK="${CLUSTER_REGISTRY_PD:-${INSTANCE_PREFIX}-kube-system-kube-registry}"
CLUSTER_REGISTRY_DISK_SIZE="${CLUSTER_REGISTRY_DISK_SIZE:-200GB}"
CLUSTER_REGISTRY_DISK_TYPE_GCE="${CLUSTER_REGISTRY_DISK_TYPE_GCE:-pd-standard}"

# Optional: Install Kubernetes UI
ENABLE_CLUSTER_UI="${KUBE_ENABLE_CLUSTER_UI:-true}"

# Optional: Install node problem detector.
#   none           - Not run node problem detector.
#   daemonset      - Run node problem detector as daemonset.
#   standalone     - Run node problem detector as standalone system daemon.
if [[ "${NODE_OS_DISTRIBUTION}" == "gci" ]]; then
  # Enable standalone mode by default for gci.
  ENABLE_NODE_PROBLEM_DETECTOR="${KUBE_ENABLE_NODE_PROBLEM_DETECTOR:-standalone}"
else
  ENABLE_NODE_PROBLEM_DETECTOR="${KUBE_ENABLE_NODE_PROBLEM_DETECTOR:-daemonset}"
fi
NODE_PROBLEM_DETECTOR_VERSION="${NODE_PROBLEM_DETECTOR_VERSION:-}"
NODE_PROBLEM_DETECTOR_TAR_HASH="${NODE_PROBLEM_DETECTOR_TAR_HASH:-}"

# Optional: Create autoscaler for cluster's nodes.
ENABLE_CLUSTER_AUTOSCALER="${KUBE_ENABLE_CLUSTER_AUTOSCALER:-false}"
if [[ "${ENABLE_CLUSTER_AUTOSCALER}" == "true" ]]; then
  AUTOSCALER_MIN_NODES="${KUBE_AUTOSCALER_MIN_NODES:-}"
  AUTOSCALER_MAX_NODES="${KUBE_AUTOSCALER_MAX_NODES:-}"
  AUTOSCALER_ENABLE_SCALE_DOWN="${KUBE_AUTOSCALER_ENABLE_SCALE_DOWN:-true}"
  AUTOSCALER_EXPANDER_CONFIG="${KUBE_AUTOSCALER_EXPANDER_CONFIG:---expander=price}"
fi

# Optional: Enable Rescheduler
ENABLE_RESCHEDULER="${KUBE_ENABLE_RESCHEDULER:-true}"

# Optional: Enable allocation of pod IPs using IP aliases.
#
# BETA FEATURE.
#
# IP_ALIAS_SIZE is the size of the podCIDR allocated to a node.
# IP_ALIAS_SUBNETWORK is the subnetwork to allocate from. If empty, a
#   new subnetwork will be created for the cluster.
ENABLE_IP_ALIASES=${KUBE_GCE_ENABLE_IP_ALIASES:-false}
if [ ${ENABLE_IP_ALIASES} = true ]; then
  # Size of ranges allocated to each node. Currently supports only /32 and /24.
  IP_ALIAS_SIZE=${KUBE_GCE_IP_ALIAS_SIZE:-/24}
  IP_ALIAS_SUBNETWORK=${KUBE_GCE_IP_ALIAS_SUBNETWORK:-${INSTANCE_PREFIX}-subnet-default}
  # Reserve the services IP space to avoid being allocated for other GCP resources.
  SERVICE_CLUSTER_IP_SUBNETWORK=${KUBE_GCE_SERVICE_CLUSTER_IP_SUBNETWORK:-${INSTANCE_PREFIX}-subnet-services}
  # NODE_IP_RANGE is used when ENABLE_IP_ALIASES=true. It is the primary range in
  # the subnet and is the range used for node instance IPs.
  NODE_IP_RANGE="$(get-node-ip-range)"
  # Add to the provider custom variables.
  PROVIDER_VARS="${PROVIDER_VARS} ENABLE_IP_ALIASES"
fi

# Admission Controllers to invoke prior to persisting objects in cluster
# If we included ResourceQuota, we should keep it at the end of the list to prevent incrementing quota usage prematurely.
ADMISSION_CONTROL=Initializers,NamespaceLifecycle,LimitRanger,ServiceAccount,PersistentVolumeLabel,DefaultStorageClass,DefaultTolerationSeconds,NodeRestriction,ResourceQuota

# Optional: if set to true kube-up will automatically check for existing resources and clean them up.
KUBE_UP_AUTOMATIC_CLEANUP=${KUBE_UP_AUTOMATIC_CLEANUP:-false}

# Storage backend. 'etcd2' supported, 'etcd3' experimental.
STORAGE_BACKEND=${STORAGE_BACKEND:-}

# Networking plugin specific settings.
NETWORK_PROVIDER="${NETWORK_PROVIDER:-kubenet}" # none, opencontrail, kubenet
OPENCONTRAIL_TAG="${OPENCONTRAIL_TAG:-R2.20}"
OPENCONTRAIL_KUBERNETES_TAG="${OPENCONTRAIL_KUBERNETES_TAG:-master}"
OPENCONTRAIL_PUBLIC_SUBNET="${OPENCONTRAIL_PUBLIC_SUBNET:-10.1.0.0/16}"

# Network Policy plugin specific settings.
NETWORK_POLICY_PROVIDER="${NETWORK_POLICY_PROVIDER:-none}" # calico

# How should the kubelet configure hairpin mode?
HAIRPIN_MODE="${HAIRPIN_MODE:-promiscuous-bridge}" # promiscuous-bridge, hairpin-veth, none
# Optional: if set to true, kube-up will configure the cluster to run e2e tests.
E2E_STORAGE_TEST_ENVIRONMENT="${KUBE_E2E_STORAGE_TEST_ENVIRONMENT:-false}"

# Evict pods whenever compute resource availability on the nodes gets below a threshold.
EVICTION_HARD="${EVICTION_HARD:-memory.available<250Mi,nodefs.available<10%,nodefs.inodesFree<5%}"

# Optional: custom scheduling algorithm
SCHEDULING_ALGORITHM_PROVIDER="${SCHEDULING_ALGORITHM_PROVIDER:-}"

# Optional: install a default StorageClass
ENABLE_DEFAULT_STORAGE_CLASS="${ENABLE_DEFAULT_STORAGE_CLASS:-true}"

# Optional: Enable legacy ABAC policy that makes all service accounts superusers.
ENABLE_LEGACY_ABAC="${ENABLE_LEGACY_ABAC:-true}" # true, false

# TODO(dawn1107): Remove this once the flag is built into CVM image.
# Kernel panic upon soft lockup issue
SOFTLOCKUP_PANIC="${SOFTLOCKUP_PANIC:-false}" # true, false

# Indicates if the values (i.e. KUBE_USER and KUBE_PASSWORD for basic
# authentication) in metadata should be treated as canonical, and therefore disk
# copies ought to be recreated/clobbered.
METADATA_CLOBBERS_CONFIG="${METADATA_CLOBBERS_CONFIG:-false}"

ENABLE_BIG_CLUSTER_SUBNETS="${ENABLE_BIG_CLUSTER_SUBNETS:-false}"
